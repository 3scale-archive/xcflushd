require 'spec_helper'

module Xcflushd
  describe FlusherErrorHandler do
    let(:logger) { double('logger', warn: true, error: true) }
    let(:storage) { double('storage', report: true) }
    subject { described_class.new(logger, storage) }

    let(:report) do
      { service_id: 's1', user_key: 'uk1', usage: { 'hits' => 1 } }
    end

    # Transactions do not have a service ID
    let(:transaction) { report.reject { |k, _v| k == :service_id } }

    shared_examples 'failed report' do |exception, error_level|
      context "because #{exception} was raised" do
        let(:error) { exception.new(report[:service_id], [transaction]) }

        it "logs a msg with lvl=#{error_level} for the failed report" do
          subject.handle_report_errors({ report => error })
          expect(logger).to have_received(error_level).with(error.message)
        end

        it 'returns the failed reports to the storage' do
          subject.handle_report_errors({ report => error })
          expect(storage).to have_received(:report).with([report])
        end
      end
    end

    describe '#handle_report_errors' do
      context 'when there is an error that requires the user intervention' do
        described_class.const_get(:REPORTER_ERRORS)[:non_temp].each do |e|
          include_examples 'failed report', e, :error
        end
      end

      context 'when there is an error that seems to be temporary' do
        described_class.const_get(:REPORTER_ERRORS)[:temp].each do |e|
          include_examples 'failed report', e, :warn
        end
      end
    end

    describe '#handle_auth_errors' do
      # There is only one kind of auth error and it is temporary
      let(:exception) do
        described_class.const_get(:AUTHORIZER_ERRORS)[:temp].first
            .new(report[:service_id], report[:user_key])
      end

      it 'logs a warning for the failed auths' do
        subject.handle_auth_errors({ report => exception })
        expect(logger).to have_received(:warn).with(exception.message)
      end
    end
  end
end
