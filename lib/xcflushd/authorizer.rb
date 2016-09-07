module Xcflushd
  class Authorizer

    def initialize(threescale_client, storage, auths_valid_minutes)
      @threescale_client = threescale_client
      @storage = storage
      @auths_valid_minutes = auths_valid_minutes
    end

    # Renews the authorization of all the limited metrics of the application
    # identified by the received (service_id, user_key) pair and also, the
    # authorization of those metrics passed in reported_metrics that are not
    # limited.
    # The authorizations expire after the period specified in
    # @auths_valid_minutes.
    def renew_authorizations(service_id, user_key, reported_metrics)
      # Metrics that are not limited are not returned by the 3scale authorize
      # call in the usage reports. For that reason, limited and non-limited
      # metrics need to be treated a bit differently.
      # Even if a metric is not limited, it could be not authorized. For
      # example, when its parent metric is limited.
      # We can safely assume that reported metrics that do not have an
      # associated report usage are non-limited metrics.

      metrics_usage = app_usage_reports_by_metric(service_id, user_key)
      renew_auths_limited_metrics(metrics_usage, service_id, user_key)

      non_limited_metrics = reported_metrics - metrics_usage.keys
      renew_auths_unlimited_metrics(non_limited_metrics, service_id, user_key)

      set_auth_validity(service_id, user_key)
    end

    private

    attr_reader :threescale_client, :storage, :auths_valid_minutes

    def auth_hash_key(service_id, user_key)
      "auth:#{service_id}:#{user_key}"
    end

    def renew_auth(service_id, user_key, metric, authorized)
      hash_key = auth_hash_key(service_id, user_key)
      storage.hset(hash_key, metric, authorized ? '1' : '0')
    end

    def renew_auths_limited_metrics(metrics_usage, service_id, user_key)
      metrics_usage.each do |metric, limits|
        renew_auth(service_id, user_key, metric, next_hit_auth?(limits))
      end
    end

    def renew_auths_unlimited_metrics(metrics, service_id, user_key)
      metrics.each do |metric|
        authorized = nolimits_metric_next_hit_auth?(service_id, user_key, metric)
        renew_auth(service_id, user_key, metric, authorized)
      end
    end

    def app_usage_reports(service_id, user_key)
      threescale_client
          .authorize(service_id: service_id, user_key: user_key)
          .usage_reports
    end

    # Returns a hash where the keys are the metrics and the values their usage
    # reports.
    def app_usage_reports_by_metric(service_id, user_key)
      # We are grouping the reports for clarity. We can change this in the
      # future if it affects performance.
      app_usage_reports(service_id, user_key).group_by do |report|
        report.metric
      end
    end

    def next_hit_auth?(limits)
      limits.all? { |limit| limit.current_value + 1 <= limit.max_value }
    end

    def nolimits_metric_next_hit_auth?(service_id, user_key, metric)
      # Non-limited metrics are not returned in the usage reports returned by
      # authorize calls. The only way of knowing if they are authorized is to
      # call authorize with a predicted usage specifying the non-limited
      # metric.
      # Ideally, we would like 3scale backend to provide a way to retrieve
      # optionally all the metrics in a single authorize call.
      threescale_client.authorize(service_id: service_id,
                                  user_key: user_key,
                                  usage: { metric => 1 }).success?
    end

    def set_auth_validity(service_id, user_key)
      # Redis does not allow us to set a TTL for hash key fields. TTLs can only
      # be applied to the key containing the hash. This is not a problem
      # because we always renew all the metrics of an application at the same
      # time.
      hash_key = auth_hash_key(service_id, user_key)
      storage.expire(hash_key, auths_valid_minutes * 60)
    end

  end
end
