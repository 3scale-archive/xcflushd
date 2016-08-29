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

      errors = { bad_params: described_class::ThreeScaleBadParams,
                 internal: described_class::ThreeScaleInternalError }

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
        context 'and 3scale client raises ServerError' do
          it "raises #{errors[:internal]}" do
            expect(threescale_client)
                .to receive(:report)
                .with(transaction)
                .and_raise(ThreeScale::ServerError.new('error_msg'))

            expect { subject.report(transaction) }
                .to raise_error errors[:internal]
          end
        end

        context 'and 3scale client raises ArgumentError' do
          it "raises #{errors[:bad_params]}" do
            expect(threescale_client)
                .to receive(:report)
                .with(transaction)
                .and_raise(ArgumentError)

            expect { subject.report(transaction) }
                .to raise_error errors[:bad_params]
          end
        end

        context 'and 3scale client returns an error in the response' do
          let(:report_response) do
            Object.new.tap do |o|
              o.define_singleton_method(:success?) { false }
              o.define_singleton_method(:error_message) { 'error_msg' }
            end
          end

          it "raises #{errors[:bad_params]}" do
            expect(threescale_client)
                .to receive(:report)
                .with(transaction)
                .and_return(report_response)

            expect { subject.report(transaction) }
                .to raise_error errors[:bad_params]
          end
        end
      end
    end
  end
end
