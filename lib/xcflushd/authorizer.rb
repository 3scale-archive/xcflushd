require '3scale_client'

module Xcflushd
  class Authorizer

    # Exception raised when the 3scale client is called with the right params
    # but it returns a ServerError. Most of the time this means that 3scale is
    # down.
    class ThreeScaleInternalError < RuntimeError
      def initialize(service_id, user_key)
        super("Error renewing auths of service with ID #{service_id} "\
              "and user_key #{user_key}. 3scale seems to be down")
      end
    end

    def initialize(threescale_client)
      @threescale_client = threescale_client
    end

    # Returns the authorization status of all the limited metrics of the
    # application identified by the received (service_id, user_key) pair and
    # also, the authorization of those metrics passed in reported_metrics that
    # are not limited.
    # The result is a hash where the keys are metrics and the values a boolean
    # that indicates authorized/not-authorized.
    def authorizations(service_id, user_key, reported_metrics)
      # Metrics that are not limited are not returned by the 3scale authorize
      # call in the usage reports. For that reason, limited and non-limited
      # metrics need to be treated a bit differently.
      # Even if a metric is not limited, it could be not authorized. For
      # example, when its parent metric is limited.
      # We can safely assume that reported metrics that do not have an
      # associated report usage are non-limited metrics.

      metrics_usage = app_usage_reports_by_metric(service_id, user_key)
      non_limited_metrics = reported_metrics - metrics_usage.keys
      all_authorizations(service_id, user_key, metrics_usage, non_limited_metrics)
    end

    private

    attr_reader :threescale_client

    def all_authorizations(service_id, user_key, metrics_usage, non_limited_metrics)
      auths_limited_metrics(metrics_usage).merge(
          auths_non_limited_metrics(service_id, user_key, non_limited_metrics))
    end

    def auths_limited_metrics(metrics_usage)
      metrics_usage.map do |metric, limits|
        [metric, next_hit_auth?(limits)]
      end.to_h
    end

    def auths_non_limited_metrics(service_id, user_key, metrics)
      metrics.map do |metric|
        auth = nolimits_metric_next_hit_auth?(service_id, user_key, metric)
        [metric, auth]
      end.to_h
    end

    def app_usage_reports(service_id, user_key)
      with_3scale_error_rescue(service_id, user_key) do
        threescale_client
            .authorize(service_id: service_id, user_key: user_key)
            .usage_reports
      end
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
      with_3scale_error_rescue(service_id, user_key) do
        threescale_client.authorize(service_id: service_id,
                                    user_key: user_key,
                                    usage: { metric => 1 }).success?
      end
    end

    def with_3scale_error_rescue(service_id, user_key)
      begin
        yield
      rescue ThreeScale::ServerError
        raise ThreeScaleInternalError.new(service_id, user_key)
      end
    end
  end
end
