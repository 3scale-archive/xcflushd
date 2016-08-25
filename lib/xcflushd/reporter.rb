module Xcflushd
  class Reporter

    def initialize(threescale_client)
      @threescale_client = threescale_client
    end

    def report(application_usage)
      # TODO: The 3scale API imposes a limit of 1000 metrics per report call
      threescale_client.report(application_usage).success?
    end

    private

    attr_reader :threescale_client

  end
end
