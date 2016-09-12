require 'spec_helper'
require 'xcflushd/storage'

module Xcflushd
  describe Storage do
    let(:redis) { Redis.new }
    subject { described_class.new(redis) }

    describe '#reports_to_flush' do
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
          subject.send(:name_key_to_flush , key)
        end
      end

      let(:set_keys_cached_reports) do
        described_class.const_get(:SET_KEYS_CACHED_REPORTS)
      end

      let(:set_keys_flushing_reports) do
        described_class.const_get(:SET_KEYS_FLUSHING_REPORTS)
      end

      before do
        # Store set that contains the keys of the cached reports
        cached_report_keys.each do |hash|
          redis.sadd(set_keys_cached_reports, hash)
        end

        # Store the cached reports as hashes where each metric is a field
        cached_reports.each do |cached_report|
          key = report_key(cached_report[:service_id], cached_report[:user_key])
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

    describe '#renew_authorizations' do
      let(:service_id) { 'a_service_id' }
      let(:user_key) { 'a_user_key' }
      let(:auth_hash_key) do
        subject.send(:auth_hash_key, service_id, user_key)
      end

      let(:valid_min) { 5 }
      let(:authorized_metrics) { %w(am1 am2) }
      let(:non_authorized_metrics) { %w(nam1 nam2) }
      let(:authorizations) do
        auths = {}
        authorized_metrics.each { |metric| auths[metric] = true }
        non_authorized_metrics.each { |metric| auths[metric] = false }
        auths
      end

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

      it 'sets a TTL for the hash that contains the auths of the application' do
        subject.renew_auths(service_id, user_key, authorizations, valid_min)
        expect(redis.ttl(auth_hash_key)).to be_between(0, valid_min*60)
      end
    end

    def report_key(service_id, user_key)
      "#{described_class.const_get(:REPORT_KEY_PREFIX)}#{service_id}:#{user_key}"
    end
  end
end
