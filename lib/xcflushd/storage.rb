module Xcflushd

  # TODO: Think about performance and handling errors. For example, some Redis
  # commands should be executed in a pipeline.
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
      flushing_report_keys.map do |report_key|
        new_hash_name = name_key_to_flush(report_key)
        storage.rename(report_key, new_hash_name)
        new_hash_name
      end
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

    def reports(keys_to_flush)
      keys_to_flush.map do |key_to_flush|
        service_id, user_key = service_and_user_key(key_to_flush)
        { service_id: service_id,
          user_key: user_key,
          usage: storage.hgetall(key_to_flush) }
      end
    end

    def cleanup(report_keys)
      storage.del(SET_KEYS_FLUSHING_REPORTS)
      report_keys.each { |report_key| storage.del(report_key) }
    end
  end

end
