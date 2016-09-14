require 'spec_helper'
require 'xcflushd/flusher'
require 'xcflushd/reporter'

module Xcflushd
  describe Flusher do
    let(:reporter) { double('reporter') }
    let(:authorizer) { double('authorizer') }
    let(:storage) { double('storage') }
    let(:auth_valid_min) { 10 }
    let(:error_handler) do
      double('error_handler',
             :handle_report_errors => true,
             :handle_auth_errors => true)
    end

    subject do
      described_class.new(reporter, authorizer, storage, auth_valid_min, error_handler)
    end

    before do
      allow(storage)
          .to receive(:reports_to_flush)
          .and_return(pending_reports)

      allow(reporter).to receive(:report)
      allow(authorizer).to receive(:authorizations)
      allow(storage).to receive(:renew_auths)
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
          { app1: { service_id: 's1', user_key: 'uk1' },
            app2: { service_id: 's2', user_key: 'uk2' } }
        end

        let(:usages) do
          { app1: { 'm1' => '1', 'm2' => '2' },
            app2: { 'm3' => '3', 'm4' => '4' } }
        end

        let(:authorizations) do
          { app1: { 'm1' => true, 'm2' => false },
            app2: { 'm3' => false, 'm4' => true } }
        end

        let(:pending_reports) do
          apps.map { |app, id| id.merge(usage: usages[app]) }
        end

        before do
          # Define the authorizations returned by the authorizer
          apps.each do |app, id|
            allow(authorizer)
                .to receive(:authorizations)
                .with(id[:service_id], id[:user_key], usages[app].keys)
                .and_return(authorizations[app])
            end
        end

        it 'reports them' do
          subject.flush

          expect(reporter)
              .to have_received(:report)
              .exactly(apps.size).times

          pending_reports.each do |pending_report|
            expect(reporter).to have_received(:report).with(pending_report)
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
                      id[:user_key],
                      authorizations[app],
                      auth_valid_min)
          end
        end
      end

      context 'when there is an error reporting' do
        let(:report) do
          { service_id: 's1', user_key: 'uk1', usage: { 'hits' => 1 } }
        end

        let(:pending_reports) { [report] }
        let(:exception) { RuntimeError.new }

        before do
          allow(reporter)
              .to receive(:report)
              .with(report)
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
          { service_id: 's1', user_key: 'uk1', usage: { 'hits' => 1 } }
        end

        let(:ok_auth_report) do
          { service_id: 's2', user_key: 'uk2', usage: { 'hits' => 1 } }
        end

        let(:pending_reports) { [failed_auth_report, ok_auth_report] }
        let(:exception) { RuntimeError.new }
        let(:auths_for_ok_report) { { 'hits' => '1' } }

        before do
          allow(authorizer)
              .to receive(:authorizations)
              .with(failed_auth_report[:service_id],
                    failed_auth_report[:user_key],
                    failed_auth_report[:usage].keys)
              .and_raise(exception)

          allow(authorizer)
              .to receive(:authorizations)
              .with(ok_auth_report[:service_id],
                    ok_auth_report[:user_key],
                    ok_auth_report[:usage].keys)
              .and_return({ 'hits' => '1' })
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
                    ok_auth_report[:user_key],
                    auths_for_ok_report,
                    auth_valid_min)
        end
      end
    end
  end
end
