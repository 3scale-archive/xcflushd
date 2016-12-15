require 'xcflushd/threading'

module Xcflushd
  # Apart from flushing all the cached reports and renewing the authorizations
  # periodically, we need to provide a mechanism to renew a specific auth at
  # any time. The information needed is the combination of service, application
  # credentials and metric.
  #
  # When the client looks for the auth of a combination in the cache, it might
  # not be there. It could be an authorization that has never been cached or one
  # that has expired. In that case, we need to provide a way to check a
  # specific authorization without waiting for the next flush cycle.
  #
  # We use Redis publish/subscribe to solve this problem. We use 2 different
  # type of channels:
  #   1) Auth requests channel. It's the channel where the client specifies the
  #      combinations that need to be checked. xcflushd is subscribed to the
  #      channel. There is only one channel of this type.
  #   2) Responses channel. Every time there's a request for a specific
  #      combination, a channel of this type is created. The client is
  #      subscribed to this channel, and xcflushd will publish the authorization
  #      status once it gets it from 3scale.
  class PriorityAuthRenewer

    # Number of times that a response is published
    TIMES_TO_PUBLISH = 5
    private_constant :TIMES_TO_PUBLISH

    # We need two separate Redis clients: one for subscribing to a channel and
    # the other one to publish to different channels. It is specified in the
    # Redis website: http://redis.io/topics/pubsub
    def initialize(authorizer, storage, redis_pub, redis_sub,
                   auth_ttl, logger, threads)
      @authorizer = authorizer
      @storage = storage
      @redis_pub = redis_pub
      @redis_sub = redis_sub
      @auth_ttl = auth_ttl
      @logger = logger

      # We can receive several requests to renew the authorization of a
      # combination while we are already renewing it. We want to avoid
      # performing several calls to 3scale asking for the same thing. For that
      # reason, we use a map to keep track of the combinations that we are
      # renewing.
      # This map is updated from different threads. We use Concurrent::Map to
      # ensure thread-safety.
      @current_auths = Concurrent::Map.new

      min_threads, max_threads = if threads
                                   [threads.min, threads.max]
                                 else
                                   Threading.default_threads_value
                                 end

      @thread_pool = Concurrent::ThreadPoolExecutor.new(
        min_threads: min_threads,
        max_threads: max_threads)
    end

    def shutdown
      @thread_pool.shutdown
    end

    def wait_for_termination(secs = nil)
      @thread_pool.wait_for_termination(secs)
    end

    def terminate
      @thread_pool.kill
    end

    def start
      begin
        subscribe_to_requests_channel
      rescue StandardError => e
        logger.error("PriorityAuthRenewer can't subscribe to the requests "\
                     "channel - #{e.class} #{e.message} #{e.cause}")
        raise e
      end
    end

    private

    attr_reader :authorizer, :storage, :redis_pub, :redis_sub, :auth_ttl,
                :logger, :current_auths, :thread_pool

    def subscribe_to_requests_channel
      redis_sub.subscribe(StorageKeys::AUTH_REQUESTS_CHANNEL) do |on|
        on.subscribe do |channel, _subscriptions|
          logger.info("PriorityAuthRenewer correctly subscribed to #{channel}")
        end

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
          rescue Concurrent::RejectedExecutionError => e
            # This error is raised when we try to submit a task to the thread
            # pool and it is rejected.
            # After we call shutdown() on the thread pool, this error will be
            # raised. We do not want to log errors in this case.
            unless thread_pool.shuttingdown?
              logger.error('Error while treating a message received in the '\
                           "requests channel: #{e.message}")
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

    # Apart from renewing the auth of the combination received, we also renew
    # all the metrics of the associated application. The reason is that to renew
    # a single metric we need to perform one call to 3scale, and to renew all
    # the limited metrics of an application we also need one. If the metric
    # received does not have limits defined, we need to perform two calls, but
    # still it is worth to renew all of them for that price.
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
          combination = auth_channel_msg_2_combination(channel_msg)
          app_auths = app_authorizations(combination)
          renew(combination[:service_id], combination[:credentials], app_auths)
          metric_auth = app_auths[combination[:metric]]
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
        publish_auth_repeatedly(combination, metric_auth) if success
      end
    end

    def auth_channel_msg_2_combination(msg)
      StorageKeys.pubsub_auth_msg_2_auth_info(msg)
    end

    def app_authorizations(combination)
      authorizer.authorizations(combination[:service_id],
                                combination[:credentials],
                                [combination[:metric]])
    end

    def renew(service_id, credentials, auths)
      storage.renew_auths(service_id, credentials, auths, auth_ttl)
    end

    def channel_for_combination(combination)
      StorageKeys.pubsub_auths_resp_channel(combination[:service_id],
                                            combination[:credentials],
                                            combination[:metric])
    end

    def publish_auth_repeatedly(combination, authorization)
      # There is a race condition here. A renew and publish task is only run
      # when there is not another one renewing the same combination. When there
      # is another, the incoming request does not trigger a new task, but waits
      # for the publish below. The request could miss the published message
      # if events happened in this order:
      #   1) The request publishes the combination it needs in the requests
      #      channel.
      #   2) A new task is not executed, because there is another renewing
      #      the same combination.
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
          publish_auth(combination, authorization)
        rescue
          publish_failures += 1
        end
        sleep((1.0/50)*((t+1)**2))
      end

      if publish_failures > 0
        logger.warn('There was an error while publishing a response in the '\
                    "priority channel. Combination: #{combination}".freeze)
      end
    end

    def publish_auth(combination, authorization)
      msg = if authorization.authorized?
              '1'.freeze
            else
               authorization.reason ? "0:#{authorization.reason}" : '0'.freeze
            end

      redis_pub.publish(channel_for_combination(combination), msg)
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
