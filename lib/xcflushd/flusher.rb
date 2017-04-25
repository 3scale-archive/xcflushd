require 'concurrent'
require 'xcflushd/threading'

module Xcflushd
  class Flusher

    WAIT_TIME_REPORT_AUTH = 5 # in seconds
    private_constant :WAIT_TIME_REPORT_AUTH

    XcflushdError = Class.new(StandardError)

    def initialize(reporter, authorizer, storage, auth_ttl, error_handler, logger, threads)
      @reporter = reporter
      @authorizer = authorizer
      @storage = storage
      @auth_ttl = auth_ttl
      @error_handler = error_handler
      @logger = logger

      min_threads, max_threads = if threads
                                   [threads.min, threads.max]
                                 else
                                   Threading.default_threads_value
                                 end

      @thread_pool = Concurrent::ThreadPoolExecutor.new(
        min_threads: min_threads, max_threads: max_threads)
    end

    def shutdown
      @thread_pool.shutdown
    end

    def wait_for_termination(secs = nil)
      @thread_pool.wait_for_termination(secs)
    end

    def terminate
      @thread_pool.kill
    end

    # TODO: decide if we want to renew the authorizations every time.
    def flush
      reports_to_flush = run_and_log_time('Getting the reports from Redis') do
        reports
      end

      run_and_log_time('Reporting to 3scale') { report(reports_to_flush) }

      # Ideally, we would like to ensure that once we start checking
      # authorizations, they have taken into account the reports that we just
      # performed. However, in 3scale, reports are asynchronous and the current
      # API does not provide a way to know whether a report has already been
      # processed.
      # For now, let's just wait a few seconds. This will greatly mitigate the
      # problem.
      run_and_log_time('Giving reports some time to be processed') do
        sleep(WAIT_TIME_REPORT_AUTH)
      end

      auths = run_and_log_time('Getting the auths from 3scale') do
        authorizations(reports_to_flush)
      end

      run_and_log_time('Renewing the auths in Redis') { renew(auths) }
    end

    private

    attr_reader :reporter, :authorizer, :storage, :auth_ttl,
                :error_handler, :logger, :thread_pool

    def reports
      storage.reports_to_flush
    end

    def report(reports)
      report_tasks = async_report_tasks(reports)
      report_tasks.values.each(&:execute)
      report_tasks.values.each(&:value) # blocks until all finish

      failed = report_tasks.select { |_report, task| task.rejected? }
                           .map { |report, task| [report, task.reason] }
                           .to_h

      error_handler.handle_report_errors(failed) unless failed.empty?
    end

    def authorizations(reports)
      auth_tasks = async_authorization_tasks(reports)
      auth_tasks.values.each(&:execute)

      auths = []
      failed = {}
      auth_tasks.each do |report, auth_task|
        auth = auth_task.value # blocks until finished

        if auth_task.fulfilled?
          auths << { service_id: report[:service_id],
                     credentials: report[:credentials],
                     auths: auth }
        else
          failed[report] = auth_task.reason
        end
      end

      error_handler.handle_auth_errors(failed) unless failed.empty?

      auths
    end

    def renew(authorizations)
      authorizations.each do |authorization|
        begin
          storage.renew_auths(authorization[:service_id],
                              authorization[:credentials],
                              authorization[:auths],
                              auth_ttl)
        rescue Storage::RenewAuthError => e
          error_handler.handle_renew_auth_error(e)
        end
      end
    end

    def async_report_tasks(reports)
      reports.map do |report|
        task = Concurrent::Future.new(executor: thread_pool) do
          reporter.report(report[:service_id],
                          report[:credentials],
                          report[:usage])
        end
        [report, task]
      end.to_h
    end

    # Returns a Hash. The keys are the reports and the values their associated
    # async authorization tasks.
    def async_authorization_tasks(reports)
      # Each call to authorizer.authorizations might need to contact 3scale
      # several times. The number of calls equals 1 + number of reported
      # metrics without limits.
      # This is probably good enough for now, but in the future we might want
      # to make sure that we perform concurrent calls to 3scale instead of
      # authorizer.authorizations.
      reports.map do |report|
        task = Concurrent::Future.new(executor: thread_pool) do
          authorizer.authorizations(report[:service_id],
                                    report[:credentials],
                                    report[:usage].keys)
        end
        [report, task]
      end.to_h
    end

    def run_and_log_time(action, &blk)
      t = Time.now
      res = blk.call
      logger.debug("#{action} took #{(Time.now - t).round(3)} seconds")
      res
    end
  end
end
