require 'spec_helper'
require 'xcflushd/reporter'

module Xcflushd
  describe Reporter do
    describe '#report' do
      let(:transaction) do
        { service_id: 'a_service_id',
          user_key: 'a_user_key',
          usage: { 'metric1' => 1, 'metric2' => 2 } }
      end

      let(:threescale_client) { double('ThreeScale::Client') }
      subject { described_class.new(threescale_client) }

      context 'when the report is successful' do
        let(:report_response) do
          Object.new.tap { |o| o.define_singleton_method(:success?) { true } }
        end

        it 'returns true' do
          expect(threescale_client)
              .to receive(:report)
              .with(transaction)
              .and_return(report_response)

          expect(subject.report(transaction)).to be true
        end
      end

      context 'when the report fails' do
        let(:report_response) do
          Object.new.tap { |o| o.define_singleton_method(:success?) { false } }
        end

        it 'returns false' do
          expect(threescale_client)
              .to receive(:report)
              .with(transaction)
              .and_return(report_response)

          expect(subject.report(transaction)).to be false
        end
      end
    end
  end
end
