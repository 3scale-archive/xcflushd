require 'spec_helper'
require 'xcflushd/authorizer'

module Xcflushd
  describe Authorizer do
    let(:threescale_client) { double('ThreeScale::Client') }
    subject { described_class.new(threescale_client) }

    Usage = Struct.new(:metric, :period, :current_value, :max_value)

    threescale_internal_error = described_class::ThreeScaleInternalError

    let(:limits_exceeded_code) do
      described_class.const_get(:LIMITS_EXCEEDED_CODE)
    end

    let(:limits_exceeded_msg) do
      described_class.const_get(:LIMITS_EXCEEDED_MSG)
    end

    describe '#authorizations' do
      let(:service_id) { 'a_service_id' }
      let(:user_key) { 'a_user_key' }
      let(:metric) { 'a_metric' }
      let(:reported_metrics) { [metric] }
      let(:metrics_hierarchy) { {} } # Default. Only 1 metric without children.

      # Default authorized response. Overwritten in cases where auth is denied.
      let(:authorize_response) do
        double('auth_response',
               success?: true,
               error_code: nil,
               error_message: nil,
               usage_reports: app_report_usages,
               hierarchy: metrics_hierarchy)
      end

      let(:denied_auth_response_limits_exceeded) do
        double('auth_response',
               success?: false,
               error_code: limits_exceeded_code,
               error_message: limits_exceeded_msg,
               usage_reports: app_report_usages,
               hierarchy: metrics_hierarchy)
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

      shared_examples 'app with hierarchies defined' do |reported_metrics, expected_auths|
        it 'returns the correct authorization status for each metric' do
          auths = subject.authorizations(service_id, user_key, reported_metrics)
          expect(auths.size).to eq expected_auths.size

          expect(expected_auths.all? do |auth|
            auths.any? do |m|
              m.metric == auth[:metric] &&
                  m.authorized? == auth[:authorized] &&
                  m.reason == auth[:reason]
            end
          end).to be true
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
              auth.metric == metric &&
                  !auth.authorized? &&
                  auth.reason == limits_exceeded_code
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

      context 'when there is a metric hierarchy defined in the authorization' do
        # We define 3 children to take into account all possible scenarios:
        # 1) limits exceeded, 2) limits not exceeded, 3) no limits.
        # For theses tests, its convenient to define the parent and children
        # metrics both in vars and lets. We need the vars because of the
        # restrictions about what can be sent as params to 'include_examples'
        # blocks.
        parent = 'a_parent'
        children = { limits_exceeded: 'c1', limits_not_exceeded: 'c2', unlimited: 'c3' }

        let(:parent) { parent }
        let(:children) { children }

        let(:metrics_hierarchy) { { parent => children.values } }

        context 'and the parent metric usage is over the limits' do
          let(:app_report_usages) do
            [Usage.new(parent, 'hour', 11, 10),
             Usage.new(children[:limits_exceeded], 'hour', 5, 1),
             Usage.new(children[:limits_not_exceeded], 'hour', 6, 10)]
          end

          expected_auths = ([parent] + children.values).map do |metric|
            { metric: metric, authorized: false, reason: 'limits_exceeded' }
          end

          # The parent is limited, so it will have usage reports.
          # In this case, all the metrics are going to be verified no matter
          # what we report.
          reported_metrics = []
          include_examples 'app with hierarchies defined', reported_metrics, expected_auths
        end

        context 'and the parent metric usage is not over the limits' do
          let(:app_report_usages) do
            [Usage.new(parent, 'hour', 1, 10),
             Usage.new(children[:limits_exceeded], 'hour', 1, 0),
             Usage.new(children[:limits_not_exceeded], 'hour', 0, 10)]
          end

          expected_auths =
              [{ metric: parent, authorized: true, reason: nil },
               { metric: children[:limits_exceeded],
                 authorized: false,
                 reason: 'limits_exceeded' },
               { metric: children[:limits_not_exceeded], authorized: true, reason: nil }]

          # The parent is limited, so it will have usage reports.
          # In this case, all the metrics are going to be verified no matter
          # what we report.
          reported_metrics = []
          include_examples 'app with hierarchies defined', reported_metrics, expected_auths
        end

        context 'and the parent metric does not have a limit' do
          let(:app_report_usages) do
            [Usage.new(children[:limits_exceeded], 'hour', 1, 0),
             Usage.new(children[:limits_not_exceeded], 'hour', 0, 10)]
          end

          # Reminder: the 3scale_client gem does not return a parent metric in
          # the hierarchy if it is not limited.
          let(:metrics_hierarchy) { {} }

          expected_auths =
              [{ metric: children[:limits_exceeded],
                 authorized: false,
                 reason: 'limits_exceeded' },
               { metric: children[:limits_not_exceeded], authorized: true, reason: nil }]

          # In this case, the parent is not limited, which means that it does
          # not have an associated usage report. The reported metrics matter
          # in this case. The auth of the parent is not going to be checked if
          # we do not report it. The same happens for the other non-limited metric
          reported_metrics = []
          include_examples 'app with hierarchies defined', reported_metrics, expected_auths

          expected_auths +=
              [{ metric: parent, authorized: true, reason: nil },
               { metric: children[:limits_not_exceeded], authorized: true, reason: nil }]

          reported_metrics = [parent, children[:unlimited]]
          include_examples 'app with hierarchies defined', reported_metrics, expected_auths
        end
      end
    end
  end
end
