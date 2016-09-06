require 'spec_helper'
require 'xcflushd/authorizer'

module Xcflushd
  describe Authorizer do
    let(:threescale_client) { double('ThreeScale::Client') }
    let(:redis) { Redis.new }
    let(:auths_valid_min) { 5 }
    subject do
      described_class.new(threescale_client, redis, auths_valid_min)
    end

    Usage = Struct.new(:metric, :period, :current_value, :max_value)

    describe '#renew_authorizations' do
      let(:service_id) { 'a_service_id' }
      let(:user_key) { 'a_user_key' }
      let(:auth_hash_key) { subject.send(:auth_hash_key, service_id, user_key) }
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

      shared_examples 'app with metric above the usage limit' do
        it 'marks the metric as non-authorized' do
          subject.renew_authorizations(service_id, user_key, reported_metrics)
          expect(redis.hget(auth_hash_key, metric)).to eq '0'
        end

        it 'sets a ttl for the hash key of the application in the storage' do
          subject.renew_authorizations(service_id, user_key, reported_metrics)
          expect(redis.ttl(auth_hash_key)).to be_between(0, auths_valid_min*60)
        end
      end

      context 'when a metric has a usage in any period that is the same as the limit' do
        let(:app_report_usages) do
          [Usage.new(metric, 'hour', 1, 1), Usage.new(metric, 'day', 1, 2)]
        end

        include_examples 'app with metric above the usage limit'
      end

      context 'when a metric has a usage above the limit in any period' do
        let(:app_report_usages) do
          [Usage.new(metric, 'hour', 2, 1), Usage.new(metric, 'day', 1, 2)]
        end

        include_examples 'app with metric above the usage limit'
      end

      context 'when a metric is above the limits for all the periods' do
        let(:app_report_usages) do
          [Usage.new(metric, 'hour', 2, 1), Usage.new(metric, 'day', 2, 1)]
        end

        include_examples 'app with metric above the usage limit'
      end

      context 'when a metric is below the limits for all the periods' do
        let(:app_report_usages) do
          [Usage.new(metric, 'hour', 1, 2), Usage.new(metric, 'day', 1, 2)]
        end

        it 'marks the metric as authorized' do
          subject.renew_authorizations(service_id, user_key, reported_metrics)
          expect(redis.hget(auth_hash_key, metric)).to eq '1'
        end

        it 'sets a ttl for the hash key of the application in the storage' do
          subject.renew_authorizations(service_id, user_key, reported_metrics)
          expect(redis.ttl(auth_hash_key)).to be_between(0, auths_valid_min*60)
        end
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

        it 'renews the authorization for all of them' do
          subject.renew_authorizations(service_id, user_key, reported_metrics)

          authorized_metrics.each do |metric|
            expect(redis.hget(auth_hash_key, metric)).to eq '1'
          end

          unauthorized_metrics.each do |metric|
            expect(redis.hget(auth_hash_key, metric)).to eq '0'
          end
        end

        it 'sets a ttl for the hash key of the application in the storage' do
          subject.renew_authorizations(service_id, user_key, reported_metrics)
          expect(redis.ttl(auth_hash_key)).to be_between(0, auths_valid_min*60)
        end
      end

      context 'when there is a non-limited metric that has been reported' do
        let(:non_limited_metric) { 'a_non_limited_metric' }
        let(:reported_metrics) { [non_limited_metric] }

        let(:app_report_usages) { [] } # Only limited metrics have reports

        before do
          allow(threescale_client)
              .to receive(:authorize)
              .with({ service_id: service_id,
                      user_key: user_key,
                      usage: { non_limited_metric => 1 } })
              .and_return(authorize_resp)
        end

        context 'and the metric is authorized' do
          let(:authorize_resp) do
            Object.new.tap { |o| o.define_singleton_method(:success?) { true } }
          end

          it 'marks the metric as authorized' do
            subject.renew_authorizations(service_id, user_key, reported_metrics)
            expect(redis.hget(auth_hash_key, non_limited_metric)).to eq '1'
          end

          it 'sets a ttl for the hash key of the application in the storage' do
            subject.renew_authorizations(service_id, user_key, reported_metrics)
            expect(redis.ttl(auth_hash_key)).to be_between(0, auths_valid_min*60)
          end
        end

        context 'and the metric is not authorized' do
          let(:authorize_resp) do
            Object.new.tap { |o| o.define_singleton_method(:success?) { false } }
          end

          it 'marks the metric as non-authorized' do
            subject.renew_authorizations(service_id, user_key, reported_metrics)
            expect(redis.hget(auth_hash_key, non_limited_metric)).to eq '0'
          end

          it 'sets a ttl for the hash key of the application in the storage' do
            subject.renew_authorizations(service_id, user_key, reported_metrics)
            expect(redis.ttl(auth_hash_key)).to be_between(0, auths_valid_min*60)
          end
        end
      end
    end
  end
end
