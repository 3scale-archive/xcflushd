module Xcflushd
  class Flusher

    def initialize(reporter, authorizer, storage, auth_valid_min)
      @reporter = reporter
      @authorizer = authorizer
      @storage = storage
      @auth_valid_min = auth_valid_min
    end

    # TODO: decide if we want to renew the authorizations every time.
    def flush
      reports_to_flush = reports
      report(reports_to_flush)
      renew(authorizations(reports_to_flush))
    end

    private

    attr_reader :reporter, :authorizer, :storage, :auth_valid_min

    def reports
      storage.reports_to_flush
    end

    def report(reports)
      reports.each { |report| reporter.report(report) }
    end

    def authorizations(reports)
      reports.map do |report|
        reported_metrics = report[:usage].keys
        auths = authorizer.authorizations(
            report[:service_id], report[:user_key], reported_metrics)

        { service_id: report[:service_id],
          user_key: report[:user_key],
          auths: auths }
      end
    end

    def renew(authorizations)
      authorizations.each do |authorization|
        storage.renew_auths(authorization[:service_id],
                            authorization[:user_key],
                            authorization[:auths],
                            auth_valid_min)
      end
    end

  end
end
