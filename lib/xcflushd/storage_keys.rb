module Xcflushd

  # This class defines the interface of the flusher with Redis. It defines how
  # to build all the keys that contain cached reports and authorizations, and
  # also, all the keys used by the pubsub mechanism.
  class StorageKeys

    # Note: Some of the keys and messages in this class contain the credentials
    # needed to authenticate an application. Credentials always appear in
    # sorted in alphabetical order. They need to be, otherwise, we could have
    # several keys or messages that refer to the same credentials.

    # Pubsub channel in which a client publishes for asking about the
    # authorization status of an application.
    AUTH_REQUESTS_CHANNEL = 'xc_channel_auth_requests'.freeze

    # Set that contains the keys of the cached reports
    SET_KEYS_CACHED_REPORTS = 'report_keys'.freeze

    # Set that contains the keys of the cached reports to be flushed
    SET_KEYS_FLUSHING_REPORTS = 'flushing_report_keys'.freeze

    # Prefix of pubsub channels where the authorization statuses are published.
    AUTH_RESPONSES_CHANNEL_PREFIX = 'xc_channel_auth_response:'.freeze
    private_constant :AUTH_RESPONSES_CHANNEL_PREFIX

    # Prefix to identify cached reports.
    REPORT_KEY_PREFIX = 'report,'.freeze
    private_constant :REPORT_KEY_PREFIX

    # Prefix to identify cached reports that are ready to be flushed
    KEY_TO_FLUSH_PREFIX = 'to_flush:'.freeze
    private_constant :KEY_TO_FLUSH_PREFIX

    class << self

      # Returns the storage key that contains the cached authorizations for the
      # given { service_id, credentials } pair.
      def auth_hash_key(service_id, credentials)
        hash_key(:auth, service_id, credentials)
      end

      # Returns the storage key that contains the cached reports for the given
      # { service_id, credentials } pair.
      def report_hash_key(service_id, credentials)
        hash_key(:report, service_id, credentials)
      end

      # Pubsub channel to which the client subscribes to receive a response
      # after asking for an authorization.
      def pubsub_auths_resp_channel(service_id, credentials, metric)
        AUTH_RESPONSES_CHANNEL_PREFIX +
            "service_id:#{service_id}," +
            "#{credentials.to_sorted_escaped_s}," +
            "metric:#{metric}"
      end

      # Returns a hash that contains service_id, credentials, and metric from
      # a message published in the pubsub channel for auth requests.
      # Expected format of the message:
      #   service_id:<service_id>,<credentials>,metric:<metric>.
      #   With all the ',' and ':' in the values escaped.
      #   <credentials> contains the credentials needed for authentication
      #   separated by ','. For example: app_id:my_app_id,user_key:my_user_key.
      def pubsub_auth_msg_2_auth_info(msg)
        msg_split = msg.split(/(?<!\\),/)
        service_id = msg_split.first.sub('service_id:'.freeze, ''.freeze)
        creds = Credentials.from(
            msg_split[1..-2].join(',').sub('credentials:'.freeze, ''.freeze))
        metric = msg_split.last.sub('metric:'.freeze, ''.freeze)

        res = { service_id: service_id, credentials: creds, metric: metric }
        res.map do |k, v|
          # Credentials are already unescaped
          [k, v.is_a?(Credentials) ? v : v.gsub("\\,", ','.freeze)
                                          .gsub("\\:", ':'.freeze)]
        end.to_h
      end

      # Returns an array of size 2 with a service and the credentials encoded
      # given a key marked as 'to be flushed' and its suffix.
      def service_and_creds(key_to_flush, suffix)
        escaped_service, escaped_creds =
            key_to_flush.sub("#{KEY_TO_FLUSH_PREFIX}#{REPORT_KEY_PREFIX}", '')
                        .sub(suffix, '')
                        .split(/(?<!\\),/)

        # escaped_service is a string with 'service_id:' followed by the escaped
        # service ID. escaped_creds starts with 'credentials:' and is followed
        # by the escaped credentials.
        service = escaped_service
                      .sub('service_id:'.freeze, ''.freeze)
                      .gsub("\\,", ','.freeze).gsub("\\:", ':'.freeze)

        creds = Credentials.from(escaped_creds.sub(
            'credentials:'.freeze, ''.freeze))

        [service, creds]
      end

      def name_key_to_flush(report_key, suffix)
        "#{KEY_TO_FLUSH_PREFIX}#{report_key}#{suffix}"
      end

      private

      def hash_key(type, service_id, creds)
        "#{type.to_s},service_id:#{service_id},#{creds.to_sorted_escaped_s}"
      end

    end
  end
end
