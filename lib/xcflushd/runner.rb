require 'xcflushd'
require 'redis'
require '3scale_client'
require 'xcflushd/3scale_client_ext'

module Xcflushd
  class Runner
    class << self
      # Amount of time to wait before retrying the subscription to the
      # priority auth renewal pubsub channel.
      PRIORITY_SUBSCRIPTION_RETRY_WAIT = 5
      private_constant :PRIORITY_SUBSCRIPTION_RETRY_WAIT
      # Maximum time to wait for a graceful shutdown before becoming more
      # aggressive at killing thread pools.
      DEFAULT_MAX_TERM_WAIT = 30
      private_constant :DEFAULT_MAX_TERM_WAIT
      # because Ruby is not providing us wakeup from sleep itself, we
      # sleep in small intervals and check if we have been signalled
      MAX_IDLING_SIGNAL_LATENCY = 5
      private_constant :MAX_IDLING_SIGNAL_LATENCY

      def run(opts = {})
        setup_sighandlers

        @max_term_wait = opts[:max_term_wait] || DEFAULT_MAX_TERM_WAIT
        @logger = Logger.new(STDOUT)

        redis_host = opts[:redis].host
        redis_port = opts[:redis].port
        redis = Redis.new(host: redis_host, port: redis_port, driver: :hiredis)
        storage = Storage.new(redis, @logger, StorageKeys)

        threescale = ThreeScale::Client.new(provider_key: opts[:provider_key],
                                            host: opts[:backend].host,
                                            port: opts[:backend].port ||
                                              (opts[:secure] ? 443 : 80),
                                            secure: opts[:secure],
                                            persistent: true)
        reporter = Reporter.new(threescale)
        authorizer = Authorizer.new(threescale)

        redis_pub = Redis.new(host: redis_host, port: redis_port, driver: :hiredis)
        redis_sub = Redis.new(host: redis_host, port: redis_port, driver: :hiredis)

        auth_ttl = opts[:auth_ttl]

        error_handler = FlusherErrorHandler.new(@logger, storage)
        @flusher = Flusher.new(reporter, authorizer, storage,
                               auth_ttl, error_handler, @logger, opts[:threads])

        @prio_auth_renewer = PriorityAuthRenewer.new(authorizer, storage,
                                                     redis_pub, redis_sub,
                                                     auth_ttl, @logger,
                                                     opts[:prio_threads])

        @prio_auth_renewer_thread = start_priority_auth_renewer

        flush_periodically(opts[:frequency])
      end

      private

      def start_priority_auth_renewer
        Thread.new do
          loop do
            break if @exit
            begin
              @prio_auth_renewer.start
            rescue StandardError
              sleep PRIORITY_SUBSCRIPTION_RETRY_WAIT
            end
          end
        end
      end

      def flush_periodically(flush_freq)
        loop do
          break if @exit
          begin
            @logger.info('Flushing...')
            flusher_start = Time.now
            next_flush = flusher_start + flush_freq
            @flusher.flush
            flusher_runtime = Time.now - flusher_start
            @logger.info("Flush completed in #{flusher_runtime} seconds")
          rescue StandardError => e
            # Let's make sure that we treat all the standard errors to ensure that
            # the flusher keeps running.
            @logger.error(e)
          end
          loop do
            # sleep in small intervals to check if signalled
            break if @exit
            time_remaining = next_flush - Time.now
            break if time_remaining <= 0
            sleep([MAX_IDLING_SIGNAL_LATENCY, time_remaining].min)
          end
        end
        @logger.info('Exiting')
      rescue SignalException => e
        @logger.fatal("Received unhandled signal #{e.cause}, shutting down")
      rescue Exception => e
        @logger.fatal("Unhandled exception #{e.class}, shutting down: #{e.cause} - #{e}")
      ensure
        shutdown
      end

      # Shutting down xcflushd
      #
      # We issue shutdown commands to the thread pools in the auth renewer and
      # the flusher, wait a bit for a graceful termination and then proceed with
      # more drastic ways.
      #
      # Note that there is no @prio_auth_renewer_thread.join(timeout).
      #
      # This is because that thread is blocked in the Redis pubsub mechanism.
      # Since that is handled by the Redis gem and there is no way to exit it
      # unless an unhandled exception is raised or an explicit unsubscribe
      # command is issued from within one of the pubsub message handlers, we
      # can't do much to issue an unsubscribe command (it would be issued from
      # an external place and would block on the Redis gem's internal
      # synchronization primitives).
      #
      # Therefore if we did the join we would be wasting that time once the
      # thread pool is terminated, so we just go ahead and kill the thread right
      # away (in terminate).
      #
      def shutdown
        shutdown_deadline = Time.now + @max_term_wait
        tasks = [@prio_auth_renewer, @flusher]
        tasks.each do |task|
          with_logged_shutdown { task.shutdown }
        end
        tasks.each do |task|
          with_logged_shutdown do
            task.wait_for_termination(shutdown_deadline - Time.now)
          end
        end
      ensure
        terminate
      end

      def terminate
        [@prio_auth_renewer, @flusher, @prio_auth_renewer_thread].each do |task|
          with_logged_shutdown { task.terminate }
        end
      end

      def with_logged_shutdown
        yield
      rescue Exception => e
        begin
          @logger.error("while shutting down: #{e.class}, cause #{e.cause} - #{e}")
        rescue Exception
          # we want to avoid barfing if logger also breaks so that further
          # processing can continue.
        end
      end

      def setup_sighandlers
        @exit = false
        ['HUP', 'USR1', 'USR2'].each do |sig|
          Signal.trap(sig, "SIG_IGN")
        end
        ['EXIT', 'TERM', 'INT'].each do |sig|
          Signal.trap(sig) { @exit = true }
        end
      end
    end
  end
end
