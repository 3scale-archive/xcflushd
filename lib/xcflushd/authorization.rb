module Xcflushd
  Authorization = Struct.new(:allowed, :reason) do
    def initialize(authorized, reason = nil)
      super(authorized, authorized ? nil : reason)
    end

    def authorized?
      allowed
    end
  end

  class Authorization
    # This is inevitably tied to the 3scale backend code
    LIMITS_EXCEEDED_CODE = 'limits_exceeded'.freeze
    private_constant :LIMITS_EXCEEDED_CODE

    ALLOWED = new(true).freeze
    private_constant :ALLOWED
    DENIED = new(false).freeze
    private_constant :DENIED
    LIMITS_EXCEEDED = new(false, LIMITS_EXCEEDED_CODE).freeze
    private_constant :LIMITS_EXCEEDED

    private_class_method :new

    def limits_exceeded?
      reason == LIMITS_EXCEEDED_CODE
    end

    def self.allow
      ALLOWED
    end

    def self.deny_over_limits
      LIMITS_EXCEEDED
    end

    def self.deny(reason = nil)
      if reason.nil?
        DENIED
      # this test has to be done in case the code changes
      elsif reason == LIMITS_EXCEEDED_CODE
        LIMITS_EXCEEDED
      else
        new(false, reason)
      end
    end
  end
end
