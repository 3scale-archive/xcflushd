module Xcflushd
  class Authorizer

    def initialize(threescale_client, storage)
      @threescale_client = threescale_client
      @storage = storage
    end

    def renew_authorizations(service_id, user_key)
      hash_key = auth_hash_key(service_id, user_key)

      # We are grouping the reports for clarity. We can change this in the
      # future if it affects performance.
      app_usage_reports_by_metric(service_id, user_key).each do |metric, limits|
        storage.hset(hash_key, metric, next_hit_auth?(limits) ? '1' : '0')
      end
    end

    private

    attr_reader :threescale_client, :storage

    def auth_hash_key(service_id, user_key)
      "auth:#{service_id}:#{user_key}"
    end

    def app_usage_reports(service_id, user_key)
      threescale_client
          .authorize(service_id: service_id, user_key: user_key)
          .usage_reports
    end

    def app_usage_reports_by_metric(service_id, user_key)
      app_usage_reports(service_id, user_key).group_by do |report|
        report.metric
      end
    end

    def next_hit_auth?(limits)
      limits.all? { |limit| limit.current_value + 1 <= limit.max_value }
    end

  end
end
