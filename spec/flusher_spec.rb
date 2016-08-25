require 'spec_helper'
require 'xcflushd/flusher'
require 'xcflushd/reporter'

module Xcflushd
  describe Flusher do
    let(:reporter) { double('reporter') }
    let(:authorizer) { double('authorizer') }
    let(:storage) { double('storage') }
    subject { described_class.new(reporter, authorizer, storage) }

    before do
      allow(storage)
          .to receive(:reports_to_flush)
          .and_return(pending_reports)

      allow(reporter).to receive(:report)
      allow(authorizer).to receive(:renew_authorizations)
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
          expect(authorizer).not_to have_received(:renew_authorizations)
        end
      end

      describe 'when there are pending reports to flush' do
        let(:pending_reports) do
          [{ service_id: 's1',
             app_key: 'a1',
             usage: { 'm1' => '1', 'm2' => '2' } },
           { service_id: 's1',
             app_key: 'a2',
             usage: { 'm1' => '10', 'm2' => '20' } }]
        end

        it 'reports them' do
          subject.flush

          expect(reporter)
              .to have_received(:report)
              .exactly(pending_reports.size).times

          pending_reports.each do |pending_report|
            expect(reporter).to have_received(:report).with(pending_report)
          end
        end

        it 'renews the authorization for the apps of those reports' do
          subject.flush

          expect(authorizer)
              .to have_received(:renew_authorizations)
              .exactly(pending_reports.size).times

          pending_reports.each do |pending_report|
            expect(authorizer)
                .to have_received(:renew_authorizations)
                .with(pending_report[:service_id], pending_report[:app_key])
          end
        end
      end
    end
  end
end
