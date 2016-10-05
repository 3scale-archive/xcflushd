module Xcflushd
  # The error handling could be improved to try to avoid losing reports
  # However, there are trade-offs to be made. Complex error handling can
  # complicate a lot the code. Also, there are no guarantees that the code in
  # the rescue clauses will be executed correctly. For example, if an smembers
  # operations fails because Redis is not accessible, and the error handling
  # consists of performing other operations to Redis, the error handling could
  # fail too.
  # Some characteristics of Redis, like the absence of rollbacks limit the
  # kind of things we can do in case of error.
  # In the future, we might explore other options like lua scripts or keeping a
  # journal (in Redis or disk).
  class Storage

    # Set that contains the keys of the cached reports
    SET_KEYS_CACHED_REPORTS = 'report_keys'.freeze
    private_constant :SET_KEYS_CACHED_REPORTS

    # Set that contains the keys of the cached reports to be flushed
    SET_KEYS_FLUSHING_REPORTS = 'flushing_report_keys'.freeze
    private_constant :SET_KEYS_FLUSHING_REPORTS

    # Prefix to identify cached authorizations
    AUTH_KEY_PREFIX = 'auth:'.freeze
    private_constant :AUTH_KEY_PREFIX

    # Prefix to identify cached reports
    REPORT_KEY_PREFIX = 'report:'.freeze
    private_constant :REPORT_KEY_PREFIX

    # Prefix to identify cached reports that are ready to be flushed
    KEY_TO_FLUSH_PREFIX = 'to_flush:'.freeze
    private_constant :KEY_TO_FLUSH_PREFIX

    # Some Redis operations might block the server for a long time if they need
    # to operate on big collections of keys or values.
    # For that reason, when using pipelines, instead of sending all the keys in
    # a single pipeline, we send them in batches.
    # If the batch is too big, we might block the server for a long time. If it
    # is too little, we will waste time in network round-trips to the server.
    REDIS_BATCH_KEYS = 500
    private_constant :REDIS_BATCH_KEYS

    RETRIEVING_REPORTS_ERROR = 'Reports cannot be retrieved.'.freeze
    private_constant :RETRIEVING_REPORTS_ERROR

    SOME_REPORTS_MISSING_ERROR = 'Some reports could not be retrieved'.freeze
    private_constant :SOME_REPORTS_MISSING_ERROR

    CLEANUP_ERROR = 'Failed to delete some keys that are no longer needed.'.freeze
    private_constant :CLEANUP_ERROR

    class RenewAuthError < Flusher::XcflushdError
      def initialize(service_id, user_key)
        super("Error while renewing the auth for service ID: #{service_id} "\
              "and user key: #{user_key}")
      end
    end

    def initialize(storage, logger)
      @storage = storage
      @logger = logger
    end

    # This performs a cleanup of the reports to be flushed.
    # We can decide later whether it is better to leave this responsibility
    # to the caller of the method.
    #
    # Returns an array of hashes where each of them has a service_id, an
    # user_key, and a usage. The usage is another hash where the keys are the
    # metrics and the values are guaranteed to respond to to_i and to_s.
    def reports_to_flush
      # The Redis rename command overwrites the key with the new name if it
      # exists. This means that if the rename operation fails in a flush cycle,
      # and succeeds in a next one, the data that the key had in the first
      # flush cycle will be lost.
      # For that reason, every time we need to rename a key, we will use a
      # unique suffix. This way, when the rename operation fails, the key
      # will not be overwritten later, and we will be able to recover its
      # content.
      suffix = suffix_for_unique_naming

      report_keys = report_keys_to_flush(suffix)
      reports(report_keys, suffix)
    end

    def renew_auths(service_id, user_key, authorizations, valid_minutes)
      hash_key = auth_hash_key(service_id, user_key)

      authorizations.each_slice(REDIS_BATCH_KEYS) do |authorizations_slice|
        authorizations_slice.each do |auth|
          storage.hset(hash_key, auth.metric, auth_value(auth))
        end
      end

      set_auth_validity(service_id, user_key, valid_minutes)

    rescue Redis::BaseError
      raise RenewAuthError.new(service_id, user_key)
    end

    def report(reports)
      reports.each do |report|
        increase_usage(report)
        add_to_set_keys_cached_reports(report)
      end
    end

    private

    attr_reader :storage, :logger

    def report_keys_to_flush(suffix)
      begin
        return [] if storage.scard(SET_KEYS_CACHED_REPORTS) == 0
        storage.rename(SET_KEYS_CACHED_REPORTS,
                       set_keys_flushing_reports(suffix))
      rescue Redis::BaseError
        # We could not even start the process of getting the reports, so just
        # log an error and return [].
        logger.error(RETRIEVING_REPORTS_ERROR)
        return []
      end

      flushing_reports = flushing_report_keys(suffix)

      keys_with_flushing_prefix = flushing_reports.map do |key|
        name_key_to_flush(key, suffix)
      end

      # Hash with old names as keys and new ones as values
      key_names = Hash[flushing_reports.zip(keys_with_flushing_prefix)]
      rename(key_names)

      key_names.values
    end

    def flushing_report_keys(suffix)
      res = storage.smembers(set_keys_flushing_reports(suffix))
    rescue Redis::BaseError
      logger.error(RETRIEVING_REPORTS_ERROR)
      []
    else
      # We only delete the set if there is not an error. If there is an error,
      # it's not deleted, so it can be recovered later.
      delete([set_keys_flushing_reports(suffix)])
      res
    end

    def name_key_to_flush(report_key, suffix)
      "#{KEY_TO_FLUSH_PREFIX}#{report_key}#{suffix}"
    end

    def service_and_user_key(key_to_flush, suffix)
      key_to_flush.sub("#{KEY_TO_FLUSH_PREFIX}#{REPORT_KEY_PREFIX}", '')
                  .sub(suffix, '')
                  .split(':')
    end

    # Returns a report (hash with service_id, user_key, and usage) for each of
    # the keys received.
    def reports(keys_to_flush, suffix)
      result = []

      keys_to_flush.each_slice(REDIS_BATCH_KEYS) do |keys|
        begin
          usages = storage.pipelined { keys.each { |k| storage.hgetall(k) } }
        rescue Redis::BaseError
          # The reports in a batch where hgetall failed will not be reported
          # now, but they will not be lost. They keys will not be deleted, so
          # we will be able to retrieve them later and retry.
          # We cannot know which ones failed because we are using a pipeline.
          logger.error(SOME_REPORTS_MISSING_ERROR)
        else
          keys.each_with_index do |key, i|
            # The usage could be empty if we failed to rename the key in the
            # previous step. hgetall returns {} for keys that do not exist.
            unless usages[i].empty?
              service_id, user_key = service_and_user_key(key, suffix)
              result << { service_id: service_id,
                          user_key: user_key,
                          usage: usages[i] }
            end
          end
          delete(keys)
        end
      end

      result
    end

    def rename(keys)
      keys.each_slice(REDIS_BATCH_KEYS) do |keys_slice|
        begin
          storage.pipelined do
            keys_slice.each do |old_name, new_name|
              storage.rename(old_name, new_name)
            end
          end
        rescue Redis::BaseError
          # The cached reports will not be reported now, but they will not be
          # lost. They will be reported next time there are hits for that
          # specific metric.
          # We cannot know which ones failed because we are using a pipeline.
          logger.warn(SOME_REPORTS_MISSING_ERROR)
        end
      end
    end

    def delete(keys)
      tries ||= 3
      storage.del(keys)
    rescue Redis::BaseError
      # Failing to delete certain keys could be problematic. That's why we
      # retry in case the error is temporary, like a network hiccup.
      #
      # When we rename keys, we give them a unique suffix so they are not
      # overwritten in the next cycle and we can retrieve their content
      # later. On the other hand, when we can retrieve their content
      # successfully, we delete them. The problem is that the delete operation
      # can fail. When trying to recover contents of keys that failed to be
      # renamed we'll not be able to distinguish these 2 cases:
      # 1) The key is there because we decided not to delete it to retrieve
      #    its content later.
      # 2) The key is there because the delete operation failed.
      # We could take a look at the logs to figure out what happened, but of
      # course that is not an ideal solution.
      if tries > 0
        tries -= 1
        sleep(0.1)
        retry
      else
        logger.error("#{CLEANUP_ERROR} Keys: #{keys}")
      end
    end

    def auth_hash_key(service_id, user_key)
      "#{AUTH_KEY_PREFIX}#{service_id}:#{user_key}"
    end

    def report_hash_key(service_id, user_key)
      "#{REPORT_KEY_PREFIX}#{service_id}:#{user_key}"
    end

    def set_auth_validity(service_id, user_key, valid_minutes)
      # Redis does not allow us to set a TTL for hash key fields. TTLs can only
      # be applied to the key containing the hash. This is not a problem
      # because we always renew all the metrics of an application at the same
      # time.
      storage.expire(auth_hash_key(service_id, user_key), valid_minutes * 60)
    end

    def increase_usage(report)
      hash_key = report_hash_key(report[:service_id], report[:user_key])

      report[:usage].each_slice(REDIS_BATCH_KEYS) do |usages|
        usages.each do |usage|
          metric, value = usage
          storage.hincrby(hash_key, metric, value)
        end
      end
    end

    def add_to_set_keys_cached_reports(report)
      hash_key = report_hash_key(report[:service_id], report[:user_key])
      storage.sadd(SET_KEYS_CACHED_REPORTS, hash_key)
    end

    def auth_value(auth)
      if auth.authorized?
        '1'.freeze
      else
        auth.reason ? "0:#{auth.reason}" : '0'.freeze
      end
    end

    def suffix_for_unique_naming
      "_#{Time.now.utc.strftime('%Y%m%d%H%M%S'.freeze)}"
    end

    def set_keys_flushing_reports(suffix)
      "#{SET_KEYS_FLUSHING_REPORTS}#{suffix}"
    end
  end

end
