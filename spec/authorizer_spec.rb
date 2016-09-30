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

      # Default authorized response. Overwritten in cases where auth is denied.
      let(:authorize_response) do
        double('auth_response',
               success?: true,
               error_code: nil,
               error_message: nil,
               usage_reports: app_report_usages)
      end

      let(:denied_auth_response_limits_exceeded) do
        double('auth_response',
               success?: false,
               error_code: 'limits_exceeded',
               error_message: 'usage limits are exceeded',
               usage_reports: app_report_usages)
      end

      before do
        allow(threescale_client)
            .to receive(:authorize)
            .with({ service_id: service_id, user_key: user_key })
            .and_return(authorize_response)
      end

      # These shared_examples only apply when there only 1 metric is reported
      shared_examples 'denied auth' do |reason|
        it 'returns a denied authorization that includes the reason' do
          auth = subject.authorizations(service_id, user_key, reported_metrics).first
          expect(auth.metric).to eq metric
          expect(auth.authorized?).to be false
          expect(auth.reason).to eq reason
        end
      end

      shared_examples 'app with authorized metric' do
        it 'returns an accepted authorization' do
          auth = subject.authorizations(service_id, user_key, reported_metrics).first
          expect(auth.metric).to eq metric
          expect(auth.authorized?).to be true
        end
      end

      context 'when the authorization is denied because of usage limits exceeded' do
        let(:authorize_response) { denied_auth_response_limits_exceeded }
        reason = 'limits_exceeded'

        context 'because the usage in any period that is the same as the limit' do
          let(:app_report_usages) do
            [Usage.new(metric, 'hour', 1, 1), Usage.new(metric, 'day', 1, 2)]
          end

          include_examples 'denied auth', reason
        end

        context 'because the usage is above the limit in any period' do
          let(:app_report_usages) do
            [Usage.new(metric, 'hour', 2, 1), Usage.new(metric, 'day', 1, 2)]
          end

          include_examples 'denied auth', reason
        end

        context 'because the usage is above the limits for all the periods' do
          let(:app_report_usages) do
            [Usage.new(metric, 'hour', 2, 1), Usage.new(metric, 'day', 2, 1)]
          end

          include_examples 'denied auth', reason
        end
      end

      context 'when a metric is below the limits for all the periods' do
        let(:app_report_usages) do
          [Usage.new(metric, 'hour', 1, 2), Usage.new(metric, 'day', 1, 2)]
        end

        include_examples 'app with authorized metric'
      end

      context 'when the app has several limited metrics, some authorized and others not' do
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

        let(:authorize_response) { denied_auth_response_limits_exceeded }

        it 'returns the correct authorization status for all of them' do
          auths = subject.authorizations(service_id, user_key, reported_metrics)

          authorized_metrics.each do |metric|
            expect(auths.any? { |auth| auth.metric == metric && auth.authorized? })
                .to be true
          end

          unauthorized_metrics.each do |metric|
            expect(auths.any? do |auth|
              auth.metric == metric && !auth.authorized? && auth.reason == 'limits_exceeded'
            end).to be true
          end
        end
      end

      context 'when there is a non-limited metric that has been reported' do
        let(:reported_metrics) { [metric] }
        let(:app_report_usages) { [] } # Only limited metrics have reports

        before do
          allow(threescale_client)
              .to receive(:authorize)
              .with({ service_id: service_id,
                      user_key: user_key,
                      usage: { metric => 1 } })
              .and_return(authorize_response)
        end

        context 'and the metric is authorized' do
          include_examples 'app with authorized metric'
        end

        context 'and the metric is not authorized because of usage limits exceeded' do
          reason = 'limits_exceeded'
          let(:authorize_response) { denied_auth_response_limits_exceeded }
          include_examples 'denied auth', reason
        end

        context 'and the metric is not authorized for a reason other than limits exceeded' do
          reason = 'some_reason'
          let(:authorize_response) do
            double('auth_response',
                   success?: false, error_code: reason, error_message: 'msg')
          end

          include_examples 'denied auth', reason
        end
      end

      context 'when the authorization is denied and it is not because limits are exceeded' do
        let(:app_report_usages) { [] }
        let(:reported_metrics) { %w(m1 m2) }
        let(:reason) { 'a_deny_reason' }
        let(:auth_response) do
          double('auth_response',
                 success?: false, error_code: reason, error_message: 'msg')
        end

        before do
          allow(threescale_client)
              .to receive(:authorize)
              .with({ service_id: service_id, user_key: user_key })
              .and_return(auth_response)
        end

        it 'returns a denied auth for each of the reported metrics' do
          auths = subject.authorizations(service_id, user_key, reported_metrics)

          expect(auths.size).to eq reported_metrics.size

          reported_metrics.each do |metric|
            expect(auths.any? do |m|
              m.metric == metric && !m.authorized? && m.reason == reason
            end).to be true
          end
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
