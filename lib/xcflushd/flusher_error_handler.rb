module Xcflushd
  class FlusherErrorHandler

    REPORTER_ERRORS = { temp: [Reporter::ThreeScaleInternalError].freeze,
                        non_temp: [Reporter::ThreeScaleBadParams,
                                   Reporter::ThreeScaleAuthError].freeze }.freeze
    private_constant :REPORTER_ERRORS

    AUTHORIZER_ERRORS = { temp: [Authorizer::ThreeScaleInternalError].freeze,
                          non_temp: [].freeze }.freeze
    private_constant :AUTHORIZER_ERRORS

    NON_TEMP_ERRORS = (REPORTER_ERRORS[:non_temp] +
                       AUTHORIZER_ERRORS[:non_temp]).freeze
    private_constant :NON_TEMP_ERRORS

    TEMP_ERRORS = (REPORTER_ERRORS[:temp] + AUTHORIZER_ERRORS[:temp]).freeze
    private_constant :TEMP_ERRORS

    def initialize(logger)
      @logger = logger
    end

    # @param failed_reports [Hash<Report, Exception>]
    def handle_report_errors(failed_reports)
      failed_reports.values.each { |exception| log(exception) }
    end

    # @param failed_auths [Hash<Auth, Exception>]
    def handle_auth_errors(failed_auths)
      failed_auths.values.each { |exception| log(exception) }
    end

    private

    attr_reader :logger

    # For exceptions that are likely to require the user intervention, we log
    # errors. For example, when the report could not be made because the 3scale
    # client received an invalid provider key.
    # On the other hand, for errors that are likely to be temporary, like when
    # we could not connect with 3scale, we log a warning.
    def log(exception)
      case exception
        when *NON_TEMP_ERRORS
          logger.error(exception.message)
        when *TEMP_ERRORS
          logger.warn(exception.message)
        else
          logger.error(exception.message)
      end
    end

  end
end
