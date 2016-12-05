require 'xcflushd'
require 'redis'
require '3scale_client'
require 'xcflushd/3scale_client_ext'

module Xcflushd
  class Runner
    class << self

      def run(opts = {})
        redis_port = opts[:redis].port
        redis = Redis.new(
          host: opts[:redis].host, port: redis_port, driver: :hiredis)
        logger = Logger.new(STDOUT)
        storage = Storage.new(redis, logger, StorageKeys)
        threescale = ThreeScale::Client.new(provider_key: opts[:provider_key],
                                            host: opts[:backend].host,
                                            port: opts[:backend].port ||
                                              (opts[:secure] ? 443 : 80),
                                            secure: opts[:secure],
                                            persistent: true)
        reporter = Reporter.new(threescale)
        authorizer = Authorizer.new(threescale)
        error_handler = FlusherErrorHandler.new(logger, storage)
        flusher = Flusher.new(reporter, authorizer, storage,
                              opts[:auth_ttl], error_handler, opts[:threads])

        redis_pub = Redis.new(
          host: opts[:redis].host, port: redis_port, driver: :hiredis)
        redis_sub = Redis.new(
          host: opts[:redis].host, port: redis_port, driver: :hiredis)

        start_priority_auth_renewer(authorizer, storage, redis_pub, redis_sub,
                                    opts[:auth_ttl], logger)
        flush_periodically(flusher, opts[:frequency], logger)
      end

      private

      def start_priority_auth_renewer(authorizer, storage, pub, sub, auth_ttl, logger)
        Thread.new do
          PriorityAuthRenewer
            .new(authorizer, storage, pub, sub, auth_ttl, logger)
            .start
        end
      end

      def flush_periodically(flusher, flush_freq, logger)
        # TODO: Handle signals. When in the middle of a flush, try to complete
        # it before exiting.
        loop do
          logger.info('Flushing...')
          start_time = Time.now
          flusher.flush
          flusher_runtime = Time.now - start_time
          logger.info("Flush completed in #{flusher_runtime} seconds")
          time_remaining_sec = flush_freq - flusher_runtime
          sleep(time_remaining_sec) if time_remaining_sec > 0
        end
      rescue StandardError => e
        # Let's make sure that we treat all the standard errors to ensure that
        # the flusher keeps running.
        logger.error(e)
      rescue Exception => e
        logger.error(e)
        abort
      end

    end
  end
end
