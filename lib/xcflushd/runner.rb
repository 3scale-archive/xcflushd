require 'xcflushd'
require 'redis'
require '3scale_client'
require 'xcflushd/3scale_client_ext'

module Xcflushd
  class Runner
    class << self

      def run(threescale_host, threescale_port, provider_key,
              redis_host, redis_port, auth_valid_min, flush_freq_min)
        redis = Redis.new(host: redis_host, port: redis_port, driver: :hiredis)
        storage = Storage.new(redis)
        threescale = ThreeScale::Client.new(provider_key: provider_key,
                                            host: threescale_host,
                                            port: threescale_port,
                                            persistent: true)
        reporter = Reporter.new(threescale)
        authorizer = Authorizer.new(threescale)
        logger = Logger.new(STDOUT)
        flusher_error_handler = FlusherErrorHandler.new(logger, storage)
        flusher = Flusher.new(reporter, authorizer, storage, auth_valid_min,
                              flusher_error_handler)

        flush_periodically(flusher, flush_freq_min, logger)
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
      end

    end
  end
end
