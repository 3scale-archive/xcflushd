module Xcflushd

  # TODO: Think about how to handle errors that occur when Redis is not
  # accessible.
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

    def initialize(storage)
      @storage = storage
    end

    # This performs a cleanup of the reports to be flushed.
    # We can decide later whether it is better to leave this responsibility
    # to the caller of the method.
    #
    # Returns an array of hashes where each of them has a service_id, an
    # user_key, and a usage. The usage is another hash where the keys are the
    # metrics and the values are guaranteed to respond to to_i and to_s.
    def reports_to_flush
      report_keys = report_keys_to_flush
      result = reports(report_keys)
      cleanup(report_keys)
      result
    end

    def renew_auths(service_id, user_key, authorizations, valid_minutes)
      hash_key = auth_hash_key(service_id, user_key)

      authorizations.each_slice(REDIS_BATCH_KEYS) do |authorizations_slice|
        authorizations_slice.each do |auth|
          storage.hset(hash_key, auth.metric, auth_value(auth))
        end
      end

      set_auth_validity(service_id, user_key, valid_minutes)
    end

    def report(reports)
      reports.each do |report|
        increase_usage(report)
        add_to_set_keys_cached_reports(report)
      end
    end

    private

    attr_reader :storage

    def report_keys_to_flush
      return [] if storage.scard(SET_KEYS_CACHED_REPORTS) == 0

      storage.rename(SET_KEYS_CACHED_REPORTS, SET_KEYS_FLUSHING_REPORTS)

      keys_with_flushing_prefix = flushing_report_keys.map do |key|
        name_key_to_flush(key)
      end

      # Hash with old names as keys and new ones as values
      key_names = Hash[flushing_report_keys.zip(keys_with_flushing_prefix)]
      rename(key_names)

      key_names.values
    end

    def flushing_report_keys
      storage.smembers(SET_KEYS_FLUSHING_REPORTS)
    end

    def name_key_to_flush(report_key)
      KEY_TO_FLUSH_PREFIX + report_key
    end

    def service_and_user_key(key_to_flush)
      key_to_flush.sub("#{KEY_TO_FLUSH_PREFIX}#{REPORT_KEY_PREFIX}", '')
                  .split(':')
    end

    # Returns a report (hash with service_id, user_key, and usage) for each of
    # the keys received.
    def reports(keys_to_flush)
      usages = []
      keys_to_flush.each_slice(REDIS_BATCH_KEYS) do |keys|
        usages << storage.pipelined do
          keys.each { |key| storage.hgetall(key) }
        end
      end

      key_usages = Hash[keys_to_flush.zip(usages.flatten)]

      key_usages.map do |key, usage|
        service_id, user_key = service_and_user_key(key)
        { service_id: service_id, user_key: user_key, usage: usage }
      end
    end

    def rename(keys)
      keys.each_slice(REDIS_BATCH_KEYS) do |keys_slice|
        storage.pipelined do
          keys_slice.each do |old_name, new_name|
            storage.rename(old_name, new_name)
          end
        end
      end
    end

    def cleanup(report_keys)
      keys_to_delete = [SET_KEYS_FLUSHING_REPORTS] + report_keys
      keys_to_delete.each_slice(REDIS_BATCH_KEYS) { |keys| storage.del(*keys) }
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

  end

end
