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

    # Number of times that a response is published
    TIMES_TO_PUBLISH = 5
    private_constant :TIMES_TO_PUBLISH

    # We need two separate Redis clients: one for subscribing to a channel and
    # the other one to publish to different channels. It is specified in the
    # Redis website: http://redis.io/topics/pubsub
    def initialize(authorizer, storage, redis_pub, redis_sub, auth_valid_min, logger)
      @authorizer = authorizer
      @storage = storage
      @redis_pub = redis_pub
      @redis_sub = redis_sub
      @auth_valid_min = auth_valid_min
      @logger = logger

      # We can receive several requests to renew the authorization of a metric
      # while we are already renewing it. We want to avoid performing several
      # calls to 3scale asking for the same thing. For that reason, we use a
      # map to keep track of the metrics that we are renewing.
      # This map is updated from different threads. We use Concurrent::Map
      # to ensure thread-safety.
      @current_auths = Concurrent::Map.new

      @random = Random.new

      # TODO: Tune the options of the thread pool
      @thread_pool = Concurrent::ThreadPoolExecutor.new(
          max_threads: Concurrent.processor_count * 4)
    end

    def start
      begin
        subscribe_to_requests_channel
      rescue StandardError
        # If we cannot subscribe, there's no point in running the program.
        # TODO: Instead of aborting, we should set a flag so the flusher can
        # exit gracefully. That exit mechanism is not implemented yet.
        abort('PriorityAuthRenewer cannot subscribe to the requests channel')
      end
    end

    private

    attr_reader :authorizer, :storage, :redis_pub, :redis_sub, :auth_valid_min,
                :logger, :current_auths, :random, :thread_pool

    def subscribe_to_requests_channel
      redis_sub.subscribe(AUTH_REQUESTS_CHANNEL) do |on|
        on.message do |_channel, msg|
          begin
            # The renew and publish operations need to be done asynchronously.
            # Renewing the authorizations involves getting them from 3scale,
            # making networks requests, and also updating Redis. We cannot block
            # until we get all that done. That is why we need to treat the
            # messages received in the channel concurrently.
            unless currently_authorizing?(msg)
              async_renew_and_publish_task(msg).execute
            end
          rescue StandardError => e
            # If we do not rescue from an exception raised while treating a
            # message, the redis client instance used stops receiving messages.
            # We need to make sure that we'll rescue in all cases.
            # Keep in mind that this will not rescue from exceptions raised in
            # async tasks because they are executed in different threads.
            logger.error('Error while treating a message received in the '\
                         "requests channel: #{e.message}")
          end
        end
      end
    end

    # Apart from renewing the auth of the metric received, we also renew all
    # the metrics of the app it belongs to. The reason is that to renew only 1
    # metric we need to perform 1 call to 3scale, and to renew all the limited
    # metrics of an application we also need 1. If the metric received does not
    # have limits defined, we need to perform 2 calls, but still, it is worth
    # to renew all of them for that price.
    #
    # Note: Some exceptions can be raised inside the futures that are executed
    # by the thread pool. For example, when 3scale is not accessible, when
    # renewing the cached authorizations fails, or when publishing to the
    # response channels fails. Trying to recover from all those cases does not
    # seem to be worth it. The request that published the message will wait for
    # a response that will not arrive and eventually, it will timeout. However,
    # if the request retries, it is likely to succeed, as the kind of errors
    # listed above are (hopefully) temporary.
    def async_renew_and_publish_task(channel_msg)
      Concurrent::Future.new(executor: thread_pool) do
        success = true
        begin
          metric = auth_channel_msg_2_metric(channel_msg)
          app_auths = app_authorizations(metric)
          renew(metric[:service_id], metric[:user_key], app_auths)
          metric_auth = metric_authorization(app_auths, metric[:metric])
        rescue StandardError
          # If we do not do rescue, we would not be able to process the same
          # message again.
          success = false
        ensure
          mark_auth_task_as_finished(channel_msg)
        end

        # We only publish a message when there aren't any errors. When
        # success is false, we could have renewed some auths, so this could
        # be more fine grained and ping the subscribers that are not interested
        # in the auths that failed. Also, as we do not publish anything when
        # there is an error, the subscriber waits until it timeouts.
        # This is good enough for now, but there is room for improvement.
        publish_auth_repeatedly(metric, metric_auth) if success
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

    def publish_auth_repeatedly(metric, authorization)
      # There is a race condition here. A renew and publish task is only run
      # when there is not another one renewing the same metric. When there is
      # another, the incoming request does not trigger a new task, but waits
      # for the publish below. The request could miss the published message
      # if events happened in this order:
      #   1) The request publishes the metric it needs in the requests
      #      channel.
      #   2) A new task is not executed, because there is another renewing
      #      the same metric.
      #   3) That task publishes the result.
      #   4) The request subscribes to receive the result, but now it is
      #      too late.
      # I cannot think of an easy way to solve this. There is some time
      # between the moment the requests performs the publish and the
      # subscribe actions. To mitigate the problem we can publish several
      # times during some ms. We will see if this is good enough.
      # Trade-off: publishing too much increases the Redis load. Waiting too
      # much makes the incoming request slow.
      publish_failures = 0
      TIMES_TO_PUBLISH.times do |t|
        begin
          publish_auth(metric, authorization)
        rescue
          publish_failures += 1
        end
        sleep((1.0/50)*((t+1)**2))
      end

      if publish_failures > 0
        logger.warn('There was an error while publishing a response in the '\
                    "priority channel. Metric: #{metric}".freeze)
      end
    end

    def publish_auth(metric, authorization)
      msg = if authorization.authorized?
              '1'.freeze
            else
               authorization.reason ? "0:#{authorization.reason}" : '0'.freeze
            end

      redis_pub.publish(channel_for_metric(metric), msg)
    end

    def currently_authorizing?(channel_msg)
      # A simple solution would be something like:
      # if !current_auths[channel_msg]
      #   current_auths[channel_msg] = true;
      #   perform_work
      #   current_auths.delete(channel_msg)
      # end
      # The problem is that the read/write is not atomic. Therefore, several
      # threads could enter the if at the same time repeating work. That is
      # why we use concurrent-ruby's Map#put_if_absent, which is atomic.

      # The value we set in the map is not relevant. #put_if_absent returns
      # nil when the key is not in the map, which means that we are not
      # currently authorizing it. That is all we care about.
      current_auths.put_if_absent(channel_msg, true) != nil
    end

    def mark_auth_task_as_finished(channel_msg)
      current_auths.delete(channel_msg)
    end
  end
end
