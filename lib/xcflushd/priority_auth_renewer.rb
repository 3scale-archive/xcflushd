module Xcflushd

  # Apart from flushing all the cached reports and renewing the authorizations
  # periodically, we need to provide a mechanism to renew a specific auth at
  # any time.
  #
  # When the client looks for the auth of a metric in the cache, it might not
  # be there. It could be an authorization that has never been cached or one
  # that has expired. In that case, we need to provide a way to check a
  # specific authorization without waiting for the next flush cycle.
  #
  # We use Redis publish/subscribe to solve this problem. We use 2 different
  # type of channels:
  #   1) Auth requests channel. It's the channel where the client specifies the
  #      metrics that need to be checked. xcflushd is subscribed to the
  #      channel. There is only one channel of this type.
  #   2) Responses channel. Every time there's a request for a specific metric,
  #      a channel of this type is created. The client is subscribed to this
  #      channel, and xcflushd will publish the authorization status once it
  #      gets it from 3scale.
  class PriorityAuthRenewer

    AUTH_REQUESTS_CHANNEL = 'xc_channel_auth_requests'.freeze
    private_constant :AUTH_REQUESTS_CHANNEL

    AUTH_RESPONSES_CHANNEL_PREFIX = 'xc_channel_auth_response:'.freeze
    private_constant :AUTH_RESPONSES_CHANNEL_PREFIX

    def initialize(authorizer, storage, redis_pubsub, auth_valid_min)
      @authorizer = authorizer
      @storage = storage
      @redis_pubsub = redis_pubsub
      @auth_valid_min = auth_valid_min
      subscribe_to_requests_channel
    end

    private

    attr_reader :authorizer, :storage, :redis_pubsub, :auth_valid_min

    def subscribe_to_requests_channel
      redis_pubsub.subscribe(AUTH_REQUESTS_CHANNEL) do |on|
        # Apart from renewing the auth of the metric received, we also renew
        # all the metrics of the app it belongs to. The reason is that to renew
        # only 1 metric we need to perform 1 call to 3scale, and to renew all
        # the limited metrics of an application we also need 1. If the metric
        # received does not have limits defined, we need to perform 2 calls,
        # but still, it is worth to renew all of them for that price.
        on.message do |_channel, msg|
          # metric is a hash of service_id, user_key, and metric name
          metric = auth_channel_msg_2_metric(msg)
          app_auths = app_authorizations(metric)
          renew(metric[:service_id], metric[:user_key], app_auths)
          metric_auth = metric_authorization(app_auths, metric[:metric])
          publish_auth(metric, metric_auth)
        end
      end
    end

    # A message in the auth channel requests has this format:
    # "#{service_id}:#{user_key}:#{metric}"
    def auth_channel_msg_2_metric(msg)
      service_id, user_key, metric = msg.split(':'.freeze)
      { service_id: service_id, user_key: user_key, metric: metric }
    end

    def app_authorizations(metric)
      authorizer.authorizations(metric[:service_id],
                                metric[:user_key],
                                [metric[:metric]])
    end

    def renew(service_id, user_key, auths)
      storage.renew_auths(service_id, user_key, auths, auth_valid_min)
    end

    def metric_authorization(app_auths, metric)
      app_auths.find { |auth| auth.metric == metric }
    end

    def channel_for_metric(metric)
      "#{AUTH_RESPONSES_CHANNEL_PREFIX}#{metric[:service_id]}:"\
        "#{metric[:user_key]}:#{metric[:metric]}"
    end

    def publish_auth(metric, authorization)
      msg = if authorization.authorized?
              '1'.freeze
            else
               authorization.reason ? "0:#{authorization.reason}" : '0'.freeze
            end

      redis_pubsub.publish(channel_for_metric(metric), msg)
    end
  end
end
