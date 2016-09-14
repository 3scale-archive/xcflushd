require 'spec_helper'
require 'xcflushd/authorizer'

module Xcflushd
  describe Authorizer do
    let(:threescale_client) { double('ThreeScale::Client') }
    subject { described_class.new(threescale_client) }

    Usage = Struct.new(:metric, :period, :current_value, :max_value)

    threescale_internal_error = described_class::ThreeScaleInternalError

    describe '#authorizations' do
      let(:service_id) { 'a_service_id' }
      let(:user_key) { 'a_user_key' }
      let(:metric) { 'a_metric' }
      let(:reported_metrics) { [metric] }

      before do
        test_report_usages = app_report_usages
        authorize_resp = Object.new.tap do |o|
          o.define_singleton_method(:usage_reports) { test_report_usages }
        end

        allow(threescale_client)
            .to receive(:authorize)
            .with({ service_id: service_id, user_key: user_key })
            .and_return(authorize_resp)
      end

      shared_examples 'app with non-authorized metric' do
        it 'returns the authorization status set to false' do
          auths = subject.authorizations(service_id, user_key, reported_metrics)
          expect(auths).to eq({ metric => false })
        end
      end

      shared_examples 'app with authorized metric' do
        it 'returns the authorization status set to true' do
          auths = subject.authorizations(service_id, user_key, reported_metrics)
          expect(auths).to eq({ metric => true })
        end
      end

      context 'when a metric has a usage in any period that is the same as the limit' do
        let(:app_report_usages) do
          [Usage.new(metric, 'hour', 1, 1), Usage.new(metric, 'day', 1, 2)]
        end

        include_examples 'app with non-authorized metric'
      end

      context 'when a metric has a usage above the limit in any period' do
        let(:app_report_usages) do
          [Usage.new(metric, 'hour', 2, 1), Usage.new(metric, 'day', 1, 2)]
        end

        include_examples 'app with non-authorized metric'
      end

      context 'when a metric is above the limits for all the periods' do
        let(:app_report_usages) do
          [Usage.new(metric, 'hour', 2, 1), Usage.new(metric, 'day', 2, 1)]
        end

        include_examples 'app with non-authorized metric'
      end

      context 'when a metric is below the limits for all the periods' do
        let(:app_report_usages) do
          [Usage.new(metric, 'hour', 1, 2), Usage.new(metric, 'day', 1, 2)]
        end

        include_examples 'app with authorized metric'
      end

      context 'when the app has several limited metrics' do
        let(:authorized_metrics) { %w(am1 am2) }
        let(:unauthorized_metrics) { %w(um1 um2) }
        let(:reported_metrics) { authorized_metrics + unauthorized_metrics }

        let(:non_exceeded_report_usages) do
          authorized_metrics.map { |metric| Usage.new(metric, 'hour', 1, 2) }
        end

        let(:exceeded_report_usages) do
          unauthorized_metrics.map { |metric| Usage.new(metric, 'hour', 2, 1) }
        end

        let(:app_report_usages) do
          non_exceeded_report_usages + exceeded_report_usages
        end

        it 'returns the correct authorization status for all of them' do
          auths = subject.authorizations(service_id, user_key, reported_metrics)

          expected_auths = {}
          authorized_metrics.each { |metric| expected_auths[metric] = true }
          unauthorized_metrics.each { |metric| expected_auths[metric] = false }

          expect(auths).to eq(expected_auths)
        end
      end

      context 'when there is a non-limited metric that has been reported' do
        let(:metric) { 'a_non_limited_metric' }
        let(:reported_metrics) { [metric] }
        let(:app_report_usages) { [] } # Only limited metrics have reports

        before do
          allow(threescale_client)
              .to receive(:authorize)
              .with({ service_id: service_id,
                      user_key: user_key,
                      usage: { metric => 1 } })
              .and_return(authorize_resp)
        end

        context 'and the metric is authorized' do
          let(:authorize_resp) do
            Object.new.tap { |o| o.define_singleton_method(:success?) { true } }
          end

          include_examples 'app with authorized metric'
        end

        context 'and the metric is not authorized' do
          let(:authorize_resp) do
            Object.new.tap { |o| o.define_singleton_method(:success?) { false } }
          end

          include_examples 'app with non-authorized metric'
        end
      end

      context 'when authorizing against 3scale fails' do
        context 'while authorizing the limited metrics' do
          let(:app_report_usages) { [] } # Does not matter. It's going to raise

          before do
            allow(threescale_client)
                .to receive(:authorize)
                .with({ service_id: service_id, user_key: user_key })
                .and_raise(ThreeScale::ServerError.new('error_msg'))
          end

          it "raises #{threescale_internal_error}" do
            expect { subject.authorizations(service_id, user_key, reported_metrics) }
                .to raise_error threescale_internal_error
          end
        end

        context 'while authorizing a non-limited metric' do
          let(:metric) { 'a_non_limited_metric' }
          let(:reported_metrics) { [metric] }

          # No usages because there is only 1 metric, and it is not limited
          let(:app_report_usages) { [] }

          before do
            # Raise only when authorizing the non-limited metric. This case can
            # be distinguished because it sends a predicted usage to the call.
            allow(threescale_client)
                .to receive(:authorize)
                .with({ service_id: service_id,
                        user_key: user_key,
                        usage: { metric => 1 } })
                .and_raise(ThreeScale::ServerError.new('error_msg'))
          end

          it "raises #{threescale_internal_error}" do
            expect { subject.authorizations(service_id, user_key, reported_metrics) }
                .to raise_error threescale_internal_error
          end
        end
      end
    end
  end
end
