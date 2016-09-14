require 'xcflushd'
require 'redis'
require '3scale_client'
require 'xcflushd/3scale_client_ext'

module Xcflushd
  class Runner
    class << self

      def run(threescale_host, threescale_port, provider_key,
              redis_host, redis_port, auth_valid_min)
        redis = Redis.new(host: redis_host, port: redis_port, driver: :hiredis)
        storage = Storage.new(redis)
        threescale = ThreeScale::Client.new(provider_key: provider_key,
                                            host: threescale_host,
                                            port: threescale_port,
                                            persistent: true)
        reporter = Reporter.new(threescale)
        authorizer = Authorizer.new(threescale)
        flusher = Flusher.new(reporter, authorizer, storage, auth_valid_min)

        flusher.flush
      end

    end
  end
end
