require 'xcflushd'
require 'redis'
require '3scale_client'
require 'xcflushd/3scale_client_ext'

module Xcflushd
  class Runner
    class << self

      def run(opts = {})
        redis = Redis.new(
            host: opts[:redis_host], port: opts[:redis_port], driver: :hiredis)
        logger = Logger.new(STDOUT)
        storage = Storage.new(redis, logger, StorageKeys)
        threescale = ThreeScale::Client.new(provider_key: opts[:provider_key],
                                            host: opts[:threescale_host],
                                            port: opts[:threescale_port],
                                            persistent: true)
        reporter = Reporter.new(threescale)
        authorizer = Authorizer.new(threescale)
        error_handler = FlusherErrorHandler.new(logger, storage)
        flusher = Flusher.new(
            reporter, authorizer, storage, opts[:auth_valid_minutes], error_handler)

        Thread.new do
          redis_pub = Redis.new(
              host: opts[:redis_host], port: opts[:redis_port], driver: :hiredis)
          redis_sub = Redis.new(
              host: opts[:redis_host], port: opts[:redis_port], driver: :hiredis)
          PriorityAuthRenewer
              .new(authorizer, storage, redis_pub, redis_sub, opts[:auth_valid_minutes], logger)
              .start
        end

        flush_periodically(flusher, opts[:reporting_freq_minutes], logger)
      end

      private

      def flush_periodically(flusher, flush_freq_min, logger)
        # TODO: Handle signals. When in the middle of a flush, try to complete
        # it before exiting.
        loop do
          logger.info('Flushing...')
          start_time = Time.now
          flusher.flush
          flusher_runtime = Time.now - start_time
          logger.info("Flush completed in #{flusher_runtime} seconds")
          time_remaining_sec = flush_freq_min*60 - flusher_runtime
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
