require 'uri'
require 'xcflushd/runner'

module Xcflushd
  module GLIHelpers
    POSITIVE_N_RE = /\A[1-9]\d*\z/.freeze

    class PositiveMinMaxInt
      # this allows 0 or more as MIN, 1 or more as MAX
      POSITIVE_MIN_MAX_RE = /\A(?<min>\d+):(?<max>[1-9]\d*)\z/.freeze
      private_constant :POSITIVE_MIN_MAX_RE

      def self.match(str)
        md = POSITIVE_MIN_MAX_RE.match str
        return false if md.nil?
        min, max = [md[:min].to_i, md[:max].to_i]
        return false if max < min
        new min, max
      end

      attr_reader :min, :max

      def initialize(min, max)
        @min, @max = min, max
      end

      def to_a
        [self]
      end
    end

    # URI parsing for GLI
    class GenericURI
      # https://tools.ietf.org/html/rfc3986#appendix-A
      SCHEME_RE = /[[:alpha:]][[[:alpha:]][[:digit:]]\+-\.]*:\/\//
      private_constant :SCHEME_RE

      def self.new(s, default_port = nil)
        # URI.parse won't correctly parse a URI without a scheme
        unless SCHEME_RE.match s
          s = "generic://#{s}"
        end
        uri = URI.parse(s)
        # exit with an error if no host parsed
        return false unless uri.host
        if !uri.port && default_port
          uri.port = default_port
        end
        uri.define_singleton_method :to_a do
          [self]
        end
        uri
      end
    end

    class RedisURI
      DEFAULT_PORT = 6379
      private_constant :DEFAULT_PORT

      def self.match(s)
        GenericURI.new(s, DEFAULT_PORT)
      end
    end

    class BackendURI
      def self.match(s)
        GenericURI.new(s)
      end
    end

    def start_xcflusher(options)
      Xcflushd::Runner.run(Hash[options.map { |k, v| [k.to_s.tr('-', '_').to_sym, v] }])
    end

    def set_title(title)
      if Process.respond_to? :setproctitle
        Process.setproctitle title
      else
        $0 = title
      end
    end
  end
end
