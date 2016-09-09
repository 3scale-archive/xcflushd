require 'concurrent'

module Xcflushd
  class Flusher

    def initialize(reporter, authorizer, storage, auth_valid_min)
      @reporter = reporter
      @authorizer = authorizer
      @storage = storage
      @auth_valid_min = auth_valid_min

      # TODO: tune the pool options.
      @thread_pool = Concurrent::ThreadPoolExecutor.new(
          max_threads: Concurrent.processor_count * 4)
    end

    # TODO: decide if we want to renew the authorizations every time.
    def flush
      reports_to_flush = reports
      report(reports_to_flush)
      renew(authorizations(reports_to_flush))
    end

    private

    attr_reader :reporter, :authorizer, :storage, :auth_valid_min, :thread_pool

    def reports
      storage.reports_to_flush
    end

    def report(reports)
      report_tasks = async_report_tasks(reports)
      report_tasks.each(&:execute)
      report_tasks.each do |report_task|
        # TODO: wait until it is done (report_task.value) and then, if
        # rejected, treat the exception
        report_task.value
      end
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

    def async_report_tasks(reports)
      reports.map do |report|
        Concurrent::Future.new(executor: thread_pool) do
          reporter.report(report)
        end
      end
    end

  end
end
