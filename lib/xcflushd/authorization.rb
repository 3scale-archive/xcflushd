module Xcflushd
  Authorization = Struct.new(:authorized, :reason) do
    def initialize(authorized, reason = nil)
      super(authorized, authorized ? nil : reason)
    end

    def authorized?
      authorized
    end
  end

  class Authorization
    # This is inevitably tied to the 3scale backend code
    LIMITS_EXCEEDED_CODE = 'limits_exceeded'.freeze
    private_constant :LIMITS_EXCEEDED_CODE

    AUTHORIZED = new(true).freeze
    private_constant :AUTHORIZED
    DENIED = new(false).freeze
    private_constant :DENIED
    LIMITS_EXCEEDED = new(false, LIMITS_EXCEEDED_CODE).freeze
    private_constant :LIMITS_EXCEEDED

    private_class_method :new

    def limits_exceeded?
      reason == LIMITS_EXCEEDED_CODE
    end

    def self.ok!
      AUTHORIZED
    end

    def self.denied!(reason = nil)
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
