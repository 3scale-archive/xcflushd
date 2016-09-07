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
        reported_metrics = report[:usage].keys
        authorizer.renew_authorizations(
            report[:service_id], report[:user_key], reported_metrics)
      end
    end

  end
end
