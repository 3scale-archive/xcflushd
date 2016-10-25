require 'spec_helper'
require 'xcflushd/storage'

module Xcflushd
  describe Storage do
    let(:redis) { Redis.new }
    let(:logger) { double('logger', warn: true, error: true) }
    subject { described_class.new(redis, logger) }

    let(:suffix) { '_20160101000000' }

    before do
      # There are sleeps in the class, but we do not need to wait in the tests.
      allow_any_instance_of(described_class).to receive(:sleep)

      # The REDIS_BATCH_KEYS constant defines the number of keys that we
      # send to Redis when using pipelines. These tests are easier to reason
      # about if we set the constant to 1.
      stub_const('Xcflushd::Storage::REDIS_BATCH_KEYS', 1)

      # The suffix for unique naming is based on the current time.
      # To avoid using a library to control time, we'll just stub the method.
      allow(subject).to receive(:suffix_for_unique_naming).and_return(suffix)
    end

    let(:set_keys_cached_reports) do
      described_class.const_get(:SET_KEYS_CACHED_REPORTS)
    end

    let(:set_keys_flushing_reports) do
      described_class.const_get(:SET_KEYS_FLUSHING_REPORTS) + suffix
    end

    let(:errors) do
      { retrieving_reports: described_class.const_get(:RETRIEVING_REPORTS_ERROR),
        some_reports_missing: described_class.const_get(:SOME_REPORTS_MISSING_ERROR) }
    end

    renew_auth_error = described_class::RenewAuthError

    describe '#reports_to_flush' do
      context 'when there are cached reports' do
        # Usage values could be ints, but Redis would return strings anyway.
        let(:cached_reports) do
          [{ service_id: 's1',
             user_key: 'a1',
             usage: { 'm1' => '1', 'm2' => '2' } },
           { service_id: 's2',
             user_key: 'a2',
             usage: { 'm1' => '10', 'm2' => '20' } }]
        end

        let(:cached_report_keys) do
          cached_reports.map do |cached_report|
            report_key(cached_report[:service_id], cached_report[:user_key])
          end
        end

        let(:reports_to_be_flushed_keys) do
          cached_report_keys.map do |key|
            subject.send(:name_key_to_flush , key, suffix)
          end
        end

        before do
          # Store set that contains the keys of the cached reports
          cached_report_keys.each do |hash|
            redis.sadd(set_keys_cached_reports, hash)
          end

          # Store the cached reports as hashes where each metric is a field
          cached_reports.each do |cached_report|
            key = report_key(cached_report[:service_id],
                             cached_report[:user_key])
            cached_report[:usage].each do |metric, value|
              redis.hset(key, metric, value)
            end
          end
        end

        it 'returns all the reports to be flushed' do
          res = subject.reports_to_flush
          expect(res).to match_array cached_reports
        end

        # The following tests check that the method performs a clean-up of the
        # storage keys used. All of them assume that no reports are cached
        # while the method is running.

        it 'cleans the set of keys of the cached reports' do
          subject.reports_to_flush
          set = redis.smembers(set_keys_cached_reports)
          expect(set).to be_empty
        end

        it 'cleans the set of keys of the reports to be flushed' do
          subject.reports_to_flush
          set = redis.smembers(set_keys_flushing_reports)
          expect(set).to be_empty
        end

        it 'cleans the original keys of the cached reports' do
          subject.reports_to_flush
          values = cached_report_keys.map { |key| redis.get(key) }
          expect(values.all? { |v| v.nil? }).to be true
        end

        it 'cleans the keys of the reports to be flushed' do
          subject.reports_to_flush
          values = reports_to_be_flushed_keys.map { |key| redis.get(key) }
          expect(values.all? { |v| v.nil? }).to be true
        end
      end

      context 'when there are not any cached reports' do
        # This test is not reliable using FakeRedis. When using the redis-rb
        # gem, rename(source_key, dest_key) command raises if the source_key
        # does not exist. However, using FakeRedis, it simply returns nil.
        it 'returns an empty array' do
          expect(subject.reports_to_flush).to be_empty
        end
      end

      # In these tests, we are checking all the steps that might fail.
      # They are heavily dependent on the Redis commands used.
      context 'when there is an error' do
        let(:cached_reports) do
          [{ service_id: 's1', user_key: 'a1', usage: { 'm1' => '1' } },
           { service_id: 's2', user_key: 'a2', usage: { 'm1' => '10' } }]
        end

        let(:cached_report_keys) do
          cached_reports.map do |cached_report|
            report_key(cached_report[:service_id], cached_report[:user_key])
          end
        end

        let(:reports_to_be_flushed_keys) do
          cached_report_keys.map do |key|
            subject.send(:name_key_to_flush , key, suffix)
          end
        end

        before do
          # Store set that contains the keys of the cached reports
          cached_report_keys.each do |hash|
            redis.sadd(set_keys_cached_reports, hash)
          end

          # Store the cached reports as hashes where each metric is a field
          cached_reports.each do |cached_report|
            key = report_key(cached_report[:service_id],
                             cached_report[:user_key])
            cached_report[:usage].each do |metric, value|
              redis.hset(key, metric, value)
            end
          end
        end

        context 'checking the cardinality of the set of pending reports' do
          before do
            allow(redis)
                .to receive(:scard)
                .with(set_keys_cached_reports)
                .and_raise(Redis::BaseError)
          end

          it 'logs an error' do
            subject.reports_to_flush
            expect(logger).to have_received(:error).with(errors[:retrieving_reports])
          end

          it 'returns an empty array' do
            expect(subject.reports_to_flush).to be_empty
          end
        end

        context 'renaming the set of pending reports' do
          before do
            allow(redis)
                .to receive(:rename)
                .with(set_keys_cached_reports, set_keys_flushing_reports)
                .and_raise(Redis::BaseError)
          end

          it 'logs an error' do
            subject.reports_to_flush
            expect(logger).to have_received(:error).with(errors[:retrieving_reports])
          end

          it 'returns an empty array' do
            expect(subject.reports_to_flush).to be_empty
          end
        end

        context 'getting the hashes from the renamed set of pending reports' do
          before do
            allow(redis)
                .to receive(:smembers)
                .with(set_keys_flushing_reports)
                .and_raise(Redis::BaseError)
          end

          it 'logs an error' do
            subject.reports_to_flush
            expect(logger).to have_received(:error).with(errors[:retrieving_reports])
          end

          it 'returns an empty array' do
            expect(subject.reports_to_flush).to be_empty
          end

          it 'does not delete the renamed set of pending reports, so it can be retrieved later' do
            subject.reports_to_flush
            expect(redis.exists(set_keys_flushing_reports)).to be true
          end
        end

        context 'renaming a hash of a report to be flushed' do
          before do
            # Raise an error only for the first cached report
            allow(redis)
                .to receive(:rename)
                .with(cached_report_keys.first, reports_to_be_flushed_keys.first)
                .and_raise(Redis::BaseError)

            # Do not raise when renaming the rest of them
            cached_report_keys[1..-1].each_with_index do |key, i|
              allow(redis)
                  .to receive(:rename)
                  .with(key, reports_to_be_flushed_keys[i + 1])
                  .and_call_original
            end

            # Call original method when renaming set of keys of cached reports
            # (If we do not define this, rspec will complain because 'redis'
            # received an unexpected message)
            allow(redis)
                .to receive(:rename)
                .with(set_keys_cached_reports, set_keys_flushing_reports)
                .and_call_original
          end

          it 'logs an error' do
            subject.reports_to_flush
            expect(logger).to have_received(:warn).with(errors[:some_reports_missing])
          end

          it 'returns all the reports except the ones for which the rename op failed' do
            # We need to check [1..-1] because we set REDIS_BATCH_KEYS
            # to 1 above.
            expect(subject.reports_to_flush)
                .to match_array cached_reports[1..-1]
          end

          it 'deletes the renamed set of pending reports' do
            subject.reports_to_flush
            expect(redis.exists(set_keys_flushing_reports)).to be false
          end
        end

        context 'getting the usage of a cached report' do
          before do
            # Raise an error only for the first cached report
            allow(redis)
                .to receive(:hgetall)
                .with(reports_to_be_flushed_keys.first)
                .and_raise(Redis::BaseError)

            reports_to_be_flushed_keys[1..-1].each do |key|
              allow(redis).to receive(:hgetall).with(key).and_call_original
            end
          end

          it 'logs an error' do
            subject.reports_to_flush
            expect(logger).to have_received(:error).with(errors[:some_reports_missing])
          end

          it 'returns the reports that are in batches where none failed' do
            # We need to check [1..-1] because we set REDIS_BATCH_KEYS
            # to 1 above.
            expect(subject.reports_to_flush)
                .to match_array cached_reports[1..-1]
          end

          it 'deletes the renamed set of pending reports' do
            subject.reports_to_flush
            expect(redis.exists(set_keys_flushing_reports)).to be false
          end

          it 'deletes the renamed keys of the reports that did not fail' do
            subject.reports_to_flush
            reports_to_be_flushed_keys[1..-1].each do |key|
              expect(redis.exists(key)).to be false
            end
          end

          it 'does not delete the renamed keys of the reports that failed' do
            subject.reports_to_flush
            expect(redis.exists(reports_to_be_flushed_keys.first)).to be true
          end
        end

        context 'performing the cleanup' do
          before { allow(redis).to receive(:del).and_raise(Redis::BaseError) }

          it 'logs an error' do
            subject.reports_to_flush
            expect(logger).to have_received(:error).at_least(:once)
          end

          it 'returns the reports to be flushed' do
            expect(subject.reports_to_flush).to match_array cached_reports
          end
        end
      end
    end

    describe '#renew_authorizations' do
      let(:service_id) { 'a_service_id' }
      let(:user_key) { 'a_user_key' }
      let(:auth_hash_key) do
        subject.send(:auth_hash_key, service_id, user_key)
      end

      let(:valid_min) { 5 }
      let(:authorized_metrics) { %w(am1 am2) }
      let(:non_authorized_metrics) { %w(nam1 nam2) }
      let(:denied_auths_with_a_reason) do
        { 'nam3'=> Authorization.denied!('a_reason') }
      end

      let(:authorizations) do
        Hash[authorized_metrics.map { |metric|
          [metric, Authorization.ok!] } + non_authorized_metrics.map { |metric|
            [metric, Authorization.denied!] }
        ].merge(denied_auths_with_a_reason)
      end

      context 'when there are no errors' do
        it 'renews the authorization of the authorized metrics' do
          subject.renew_auths(service_id, user_key, authorizations, valid_min)
          authorized_metrics.each do |metric|
            expect(redis.hget(auth_hash_key, metric)).to eq '1'
          end
        end

        it 'renews the authorization of the non-authorized metrics' do
          subject.renew_auths(service_id, user_key, authorizations, valid_min)
          non_authorized_metrics.each do |metric|
            expect(redis.hget(auth_hash_key, metric)).to eq '0'
          end
        end

        it 'renews the authorization of denied metrics specifying the reason' do
          subject.renew_auths(service_id, user_key, authorizations, valid_min)
          denied_auths_with_a_reason.each do |metric, auth|
            expect(redis.hget(auth_hash_key, metric)).to eq "0:#{auth.reason}"
          end
        end

        it 'sets a TTL for the hash that contains the auths of the application' do
          subject.renew_auths(service_id, user_key, authorizations, valid_min)
          expect(redis.ttl(auth_hash_key)).to be_between(0, valid_min*60)
        end
      end

      context 'when there is an error' do
        # Fake redis error in any method that the client receives.
        before { allow(redis).to receive(:hset).and_raise(Redis::BaseError) }

        it "raises a #{renew_auth_error}" do
          expect { subject.renew_auths(service_id, user_key, authorizations, valid_min) }
              .to raise_error(renew_auth_error)
        end
      end
    end

    describe '#report' do
      let(:apps) do
        { app1: { service_id: 's1', user_key: 'uk1'},
          app2: { service_id: 's2', user_key: 'uk2'} }
      end

      let(:reported_usages) do
        { app1: { 'm1' => '1', 'm2' => '2' },
          app2: { 'm3' => '3', 'm4' => '4' }}
      end

      let(:current_usages) do
        { app1: { 'm1' => '10', 'm2' => '20' },
          app2: { 'm3' => '30', 'm4' => '40' }}
      end

      let(:reports) do
        apps.map { |app, id| id.merge(usage: reported_usages[app]) }
      end

      let(:report_keys) do
        reports.map do |report|
          report_key(report[:service_id], report[:user_key])
        end
      end

      before do
        # Set the current usage
        apps.each do |app, id|
          key = report_key(id[:service_id], id[:user_key])
          current_usages[app].each do |metric, usage|
            redis.hset(key, metric, usage)
          end
        end
      end

      it 'increases the usage of all the metrics reported' do
        subject.report(reports)
        apps.each do |app, id|
          key = report_key(id[:service_id], id[:user_key])
          reported_usages[app].each do |metric, usage|
            expect(redis.hget(key, metric))
                .to eq((usage.to_i + current_usages[app][metric].to_i).to_s)
          end
        end
      end

      it 'adds the affected cached report keys to the set of cached reports' do
        subject.report(reports)
        expect(redis.smembers(set_keys_cached_reports))
            .to include(*report_keys)
      end
    end

    def report_key(service_id, user_key)
      subject.send(:report_hash_key, service_id, user_key)
    end

  end
end
