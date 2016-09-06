require '3scale_client'

module Xcflushd
  class Reporter

    # Exception raised when the 3scale client is not called with the right
    # params. This happens when there are programming errors.
    ThreeScaleBadParams = Class.new(RuntimeError)

    # Exception raised when the 3scale client is called with the right params
    # but it returns a ServerError. Most of the time this means that 3scale is
    # down.
    ThreeScaleInternalError = Class.new(RuntimeError)

    # Exception raised when the 3scale client made the call, but did not
    # succeed. This happens when the credentials are invalid. For example, when
    # an invalid provider key is used.
    ThreeScaleAuthError = Class.new(RuntimeError)

    def initialize(threescale_client)
      @threescale_client = threescale_client
    end

    def report(application_usage)
      # TODO: The 3scale API imposes a limit of 1000 metrics per report call

      begin
        resp = threescale_client.report(application_usage)
      # TODO: get rid of the coupling with ThreeScale::ServerError
      rescue ThreeScale::ServerError => e
        raise ThreeScaleInternalError, e.message
      rescue ArgumentError => e
        raise ThreeScaleBadParams, e.message
      end

      raise ThreeScaleAuthError, resp.error_message unless resp.success?
      true
    end

    private

    attr_reader :threescale_client

  end
end
