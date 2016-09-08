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

    private

    attr_reader :storage

    def report_keys_to_flush
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
  end

end
