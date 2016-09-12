require 'spec_helper'
require 'xcflushd/flusher'
require 'xcflushd/reporter'

module Xcflushd
  describe Flusher do
    let(:reporter) { double('reporter') }
    let(:authorizer) { double('authorizer') }
    let(:storage) { double('storage') }
    let(:auth_valid_min) { 10 }

    subject do
      described_class.new(reporter, authorizer, storage, auth_valid_min)
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
    end
  end
end
