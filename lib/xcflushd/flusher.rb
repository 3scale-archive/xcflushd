module Xcflushd
  class Flusher

    def initialize(reporter, authorizer, storage)
      @reporter = reporter
      @authorizer = authorizer
      @storage = storage
    end

    # TODO: decide if we want to renew the authorizations every time.
    def flush
      reports = storage.reports_to_flush
      report(reports)
      renew_authorizations(reports)
    end

    private

    attr_reader :reporter, :authorizer, :storage

    def report(reports)
      reports.each { |report| reporter.report(report) }
    end

    def renew_authorizations(reports)
      reports.each do |report|
        authorizer.renew_authorizations(report[:service_id], report[:app_key])
      end
    end

  end
end
