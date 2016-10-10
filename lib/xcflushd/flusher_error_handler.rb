module Xcflushd
  class FlusherErrorHandler

    REPORTER_ERRORS = { temp: [Reporter::ThreeScaleInternalError].freeze,
                        non_temp: [Reporter::ThreeScaleBadParams,
                                   Reporter::ThreeScaleAuthError].freeze }.freeze
    private_constant :REPORTER_ERRORS

    AUTHORIZER_ERRORS = { temp: [Authorizer::ThreeScaleInternalError].freeze,
                          non_temp: [].freeze }.freeze
    private_constant :AUTHORIZER_ERRORS

    STORAGE_ERRORS = { temp: [Storage::RenewAuthError].freeze,
                       non_temp: [].freeze}.freeze
    private_constant :STORAGE_ERRORS

    NON_TEMP_ERRORS = [REPORTER_ERRORS, AUTHORIZER_ERRORS, STORAGE_ERRORS].map do |errors|
      errors[:non_temp]
    end.flatten
    private_constant :NON_TEMP_ERRORS

    TEMP_ERRORS = [REPORTER_ERRORS, AUTHORIZER_ERRORS, STORAGE_ERRORS].map do |errors|
      errors[:temp]
    end.flatten
    private_constant :TEMP_ERRORS

    def initialize(logger, storage)
      @logger = logger
      @storage = storage
    end

    # @param failed_reports [Hash<Report, Exception>]
    def handle_report_errors(failed_reports)
      failed_reports.values.each { |exception| log(exception) }
      storage.report(failed_reports.keys)
    end

    # @param failed_auths [Hash<Auth, Exception>]
    def handle_auth_errors(failed_auths)
      failed_auths.values.each { |exception| log(exception) }
    end

    # @param exception [Exception]
    def handle_renew_auth_error(exception)
      # Failing to renew an authorization in the cache should not be a big
      # problem. It is probably caused by a temporary issue (like a Redis
      # connection error) and the auth will probably be successfully renewed
      # next time. So for now, we just log the error.
      log(exception)
    end

    private

    attr_reader :logger, :storage

    # For exceptions that are likely to require the user intervention, we log
    # errors. For example, when the report could not be made because the 3scale
    # client received an invalid provider key.
    # On the other hand, for errors that are likely to be temporary, like when
    # we could not connect with 3scale, we log a warning.
    def log(exception)
      msg = error_msg(exception)
      case exception
        when *NON_TEMP_ERRORS
          logger.error(msg)
        when *TEMP_ERRORS
          logger.warn(msg)
        else
          logger.error(msg)
      end
    end

    def error_msg(exception)
      "#{exception.message} Cause: #{exception.cause || '-'.freeze}"
    end

  end
end
