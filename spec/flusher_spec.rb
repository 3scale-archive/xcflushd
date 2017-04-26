require 'spec_helper'
require 'xcflushd/flusher'
require 'xcflushd/reporter'

module Xcflushd
  describe Flusher do
    let(:reporter) { double('reporter', report: true) }
    let(:authorizer) { double('authorizer', authorizations: true) }
    let(:auth_valid_secs) { 10 * 60 }

    let(:storage) do
      double('storage', renew_auths: true, reports_to_flush: pending_reports)
    end

    let(:error_handler) do
      double('error_handler',
             :handle_report_errors => true,
             :handle_auth_errors => true,
             :handle_renew_auth_error => true)
    end

    let(:logger) { double('logger', debug: true) }
    let(:threads) { 8 }

    subject do
      described_class.new(reporter, authorizer, storage, auth_valid_secs,
                          error_handler, logger, threads)
    end

    before do
      # There are sleeps in the class, but we do not need to wait in the tests.
      allow_any_instance_of(described_class).to receive(:sleep)
    end

    describe '#flush' do
      describe 'when there are no pending reports to flush' do
        let(:pending_reports) { [] }

        it 'does not report anything' do
          subject.flush
          expect(reporter).not_to have_received(:report)
        end

        it 'does not renew any authorizations' do
          subject.flush
          expect(storage).not_to have_received(:renew_auths)
        end
      end

      describe 'when there are pending reports to flush' do
        let(:apps) do
          { app1: { service_id: 's1',
                    credentials: Credentials.new(user_key: 'uk1') },
            app2: { service_id: 's2',
                    credentials: Credentials.new(user_key: 'uk2') } }
        end

        let(:usages) do
          { app1: { 'm1' => '1', 'm2' => '2' },
            app2: { 'm3' => '3', 'm4' => '4' } }
        end

        let(:authorizations) do
          { app1: { 'm1' => Authorization.allow,
                    'm2' => Authorization.deny },
            app2: { 'm3' => Authorization.deny,
                    'm4' => Authorization.allow }
          }
        end

        let(:pending_reports) do
          apps.map { |app, id| id.merge(usage: usages[app]) }
        end

        before do
          # Define the authorizations returned by the authorizer
          apps.each do |app, id|
            allow(authorizer)
                .to receive(:authorizations)
                .with(id[:service_id], id[:credentials], usages[app].keys)
                .and_return(authorizations[app])
            end
        end

        it 'reports them' do
          subject.flush

          expect(reporter)
              .to have_received(:report)
              .exactly(apps.size).times

          pending_reports.each do |pending_report|
            expect(reporter)
                .to have_received(:report)
                .with(pending_report[:service_id],
                      pending_report[:credentials],
                      pending_report[:usage])
          end
        end

        it 'renews the authorization for the apps of those reports' do
          subject.flush

          expect(storage)
              .to have_received(:renew_auths)
              .exactly(apps.size).times

          apps.each do |app, id|
            expect(storage)
                .to have_received(:renew_auths)
                .with(id[:service_id],
                      id[:credentials],
                      authorizations[app],
                      auth_valid_secs)
          end
        end
      end

      context 'when there is an error reporting' do
        let(:service_id) { 'a_service_id' }
        let(:credentials) { Credentials.new(user_key: 'uk1') }
        let(:usage) { { 'hits' => 1 } }

        let(:report) do
          { service_id: service_id,
            credentials: credentials,
            usage: usage }
        end

        let(:pending_reports) { [report] }
        let(:exception) { RuntimeError.new }

        before do
          allow(reporter)
              .to receive(:report)
              .with(service_id, credentials, usage)
              .and_raise(exception)
        end

        it 'handles the error' do
          subject.flush
          expect(error_handler)
              .to have_received(:handle_report_errors)
              .with({ report => exception })
        end
      end

      context 'when there is an error authorizing' do
        let(:failed_auth_report) do
          { service_id: 's1',
            credentials: Credentials.new(user_key: 'uk1'),
            usage: { 'hits' => 1 } }
        end

        let(:ok_auth_report) do
          { service_id: 's2',
            credentials: Credentials.new(user_key: 'uk2'),
            usage: { 'hits' => 1 } }
        end

        let(:pending_reports) { [failed_auth_report, ok_auth_report] }
        let(:exception) { RuntimeError.new }
        let(:auths_for_ok_report) { { 'hits' => Authorization.allow } }

        before do
          allow(authorizer)
              .to receive(:authorizations)
              .with(failed_auth_report[:service_id],
                    failed_auth_report[:credentials],
                    failed_auth_report[:usage].keys)
              .and_raise(exception)

          allow(authorizer)
              .to receive(:authorizations)
              .with(ok_auth_report[:service_id],
                    ok_auth_report[:credentials],
                    ok_auth_report[:usage].keys)
              .and_return(auths_for_ok_report)
        end

        it 'handles the error' do
          subject.flush
          expect(error_handler)
              .to have_received(:handle_auth_errors)
              .with({ failed_auth_report => exception })
        end

        it 'only tries to renew non-failed auths' do
          subject.flush
          expect(storage).to have_received(:renew_auths).once
          expect(storage)
              .to have_received(:renew_auths)
              .with(ok_auth_report[:service_id],
                    ok_auth_report[:credentials],
                    auths_for_ok_report,
                    auth_valid_secs)
        end
      end

      context 'when there is an error while renewing the authorizations' do
        let(:report_with_failed_renew_auth) do
          { service_id: 's1', user_key: 'uk1', usage: { 'hits' => 1 } }
        end

        let(:pending_reports) { [report_with_failed_renew_auth] }

        before do
          allow(storage)
              .to receive(:renew_auths)
              .and_raise(Storage::RenewAuthError.new(
                  report_with_failed_renew_auth[:service_id],
                  report_with_failed_renew_auth[:user_key]))
        end

        it 'handles the error' do
          subject.flush
          expect(error_handler).to have_received(:handle_renew_auth_error)
        end
      end
    end
  end
end
