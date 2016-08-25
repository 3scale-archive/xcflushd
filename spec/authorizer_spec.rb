require 'spec_helper'
require 'xcflushd/authorizer'

module Xcflushd
  describe Authorizer do
    let(:threescale_client) { double('ThreeScale::Client') }
    let(:redis) { Redis.new }
    subject { described_class.new(threescale_client, redis) }

    describe '#renew_authorizations' do
      let(:service_id) { 'a_service_id' }
      let(:app_key) { 'an_app_key' }
      let(:auth_hash_key) { subject.send(:auth_hash_key, service_id, app_key) }
      let(:metric) { 'a_metric' }

      before do
        allow(threescale_client)
            .to receive(:authorize)
            .with({ service_id: service_id, app_key: app_key })
            .and_return(app_report_usages)
      end

      context 'when a metric has a usage in any period that is the same as the limit' do
        let(:app_report_usages) do
          [{ metric: metric, period: 'hour', current_value: 1, max_value: 1 },
           { metric: metric, period: 'day', current_value: 1, max_value: 2 }]
        end

        it 'marks the metric as non-authorized' do
          subject.renew_authorizations(service_id, app_key)
          expect(redis.hget(auth_hash_key, metric)).to eq '0'
        end
      end

      context 'when a metric has a usage above the limit in any period' do
        let(:app_report_usages) do
          [{ metric: metric, period: 'hour', current_value: 2, max_value: 1 },
           { metric: metric, period: 'day', current_value: 1, max_value: 2 }]
        end

        it 'marks the metric as non-authorized' do
          subject.renew_authorizations(service_id, app_key)
          expect(redis.hget(auth_hash_key, metric)).to eq '0'
        end
      end

      context 'when a metric is above the limits for all the periods' do
        let(:app_report_usages) do
          [{ metric: metric, period: 'hour', current_value: 2, max_value: 1 },
           { metric: metric, period: 'day', current_value: 2, max_value: 1 }]
        end

        it 'marks the metric as non-authorized' do
          subject.renew_authorizations(service_id, app_key)
          expect(redis.hget(auth_hash_key, metric)).to eq '0'
        end
      end

      context 'when a metric is below the limits for all the periods' do
        let(:app_report_usages) do
          [{ metric: metric, period: 'hour', current_value: 1, max_value: 2 },
           { metric: metric, period: 'day', current_value: 1, max_value: 2 }]
        end

        it 'marks the metric as authorized' do
          subject.renew_authorizations(service_id, app_key)
          expect(redis.hget(auth_hash_key, metric)).to eq '1'
        end
      end

      context 'when the app has several metrics' do
        let(:authorized_metrics) { %w(am1 am2) }
        let(:unauthorized_metrics) { %w(um1 um2) }

        let(:non_exceeded_report_usages) do
          authorized_metrics.map do |metric|
            { metric: metric, period: 'hour', current_value: 1, max_value: 2 }
          end
        end

        let(:exceeded_report_usages) do
          unauthorized_metrics.map do |metric|
            { metric: metric, period: 'hour', current_value: 2, max_value: 1 }
          end
        end

        let(:app_report_usages) do
          non_exceeded_report_usages + exceeded_report_usages
        end

        it 'renews the authorization for all of them' do
          subject.renew_authorizations(service_id, app_key)

          authorized_metrics.each do |metric|
            auth_hash_key = subject.send(:auth_hash_key, service_id, app_key)
            expect(redis.hget(auth_hash_key, metric)).to eq '1'
          end

          unauthorized_metrics.each do |metric|
            auth_hash_key = subject.send(:auth_hash_key, service_id, app_key)
            expect(redis.hget(auth_hash_key, metric)).to eq '0'
          end
        end
      end

      # TODO: test case of non-limited metrics. Investigate what the
      # 3scale_client returns in that case.
    end
  end
end
