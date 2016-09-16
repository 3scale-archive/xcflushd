module Xcflushd
  class Authorization

    attr_reader :metric, :reason

    def initialize(metric, authorized, reason = nil)
      @metric = metric
      @authorized = authorized
      @reason = authorized ? nil : reason
    end

    def authorized?
      @authorized
    end

  end
end
