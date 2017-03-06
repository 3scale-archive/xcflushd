require 'spec_helper'
require 'xcflushd/storage_keys'

module Xcflushd
  describe StorageKeys do
    subject { described_class }

    let(:auth_responses_channel_prefix) do
      subject.const_get(:AUTH_RESPONSES_CHANNEL_PREFIX)
    end

    let(:key_to_flush_prefix) { subject.const_get(:KEY_TO_FLUSH_PREFIX) }
    let(:report_key_prefix) { subject.const_get(:REPORT_KEY_PREFIX) }

    shared_examples 'hash key' do |type, service_id, credentials|
      it 'returns the key with the expected format' do
        expected = "#{type}," +
            "service_id:#{service_id}," +
            "#{credentials.to_sorted_escaped_s}"

        actual = subject.send("#{type}_hash_key", service_id, credentials)

        expect(actual).to eq expected
      end
    end

    shared_examples 'pubsub auth channel' do |service_id, credentials, metric|
      it 'returns the correct channel' do
        expected = auth_responses_channel_prefix +
            "service_id:#{service_id}," +
            "#{credentials.to_sorted_escaped_s}," +
            "metric:#{metric}"

        actual = subject.pubsub_auths_resp_channel(
            service_id, credentials, metric)

        expect(actual).to eq expected
      end
    end

    shared_examples 'pubsub message' do |service_id, credentials, metric, msg|
      it 'returns the correct auth info' do
        expect(subject.pubsub_auth_msg_2_auth_info(msg))
            .to eq ({ service_id: service_id,
                      credentials: credentials,
                      metric: metric })
      end
    end

    it 'defines the pubsub channel for the auth requests' do
      expect(subject::AUTH_REQUESTS_CHANNEL).not_to be nil
    end

    it 'defines the set that contains the cached reports' do
      expect(subject::SET_KEYS_CACHED_REPORTS).not_to be nil
    end

    it 'defines the set that contains the keys of the cached reports to be flushed' do
      expect(subject::SET_KEYS_FLUSHING_REPORTS).not_to be nil
    end

    describe '.auth_hash_key' do
      context 'when only one credential is specified' do
        include_examples 'hash key', :auth, 'a_service_id',
                         Credentials.new(user_key: 'uk1')
      end

      context 'when several credentials are specified' do
        include_examples 'hash key', :auth, 'a_service_id',
                         Credentials.new(app_id: 'ai1', app_key: 'ak1')
      end
    end

    describe '.report_hash_key' do
      context 'when only one credential is specified' do
        include_examples 'hash key', :report, 'a_service_id',
                         Credentials.new(user_key: 'uk1')
      end

      context 'when several credentials are specified' do
        include_examples 'hash key', :report, 'a_service_id',
                         Credentials.new(app_id: 'ai1', app_key: 'ak1')
      end
    end

    describe '.pubsub_auths_resp_channel' do
      context 'when only one credential is specified' do
        include_examples 'pubsub auth channel',
                         'a_service_id',
                         Credentials.new(user_key: 'a_user_key'),
                         'a_metric'
      end

      context 'when several credentials are specified' do
        include_examples 'pubsub auth channel',
                         'a_service_id',
                         Credentials.new(app_id: 'an_app_id',
                                         app_key: 'and_app_key'),
                         'a_metric'
      end
    end

    describe '.pubsub_auth_msg_2_auth_info' do
      context 'when the message does not include escaped chars' do
        service_id = 'a_service_id'
        credentials = Credentials.new(app_id: 'an_app_id')
        metric = 'a_metric'
        msg = "service_id:#{service_id}," +
            "#{credentials.to_sorted_escaped_s}," + # escapes ':' and ','
            "metric:#{metric}"

        include_examples 'pubsub message', service_id, credentials, metric, msg
      end

      context 'when the message includes escaped chars' do
        service_id = 'a_service_id'
        credentials = Credentials.new(app_id: 'an:app,id')
        metric = 'a_metric'
        msg = "service_id:#{service_id}," +
            "#{credentials.to_sorted_escaped_s}," + # escapes ':' and ','
            "metric:#{metric}"

        include_examples 'pubsub message', service_id, credentials, metric, msg
      end

      context 'when the message includes several credentials' do
        service_id = 'a_service_id'
        credentials = Credentials.new(app_id: 'ai', app_key: 'ak')
        metric = 'a_metric'
        msg = "service_id:#{service_id}," +
            "#{credentials.to_sorted_escaped_s}," + # escapes ':' and ','
            "metric:#{metric}"

        include_examples 'pubsub message', service_id, credentials, metric, msg
      end
    end

    describe '.service_and_creds' do
      let(:service_id) { 'a_service_id' }
      let(:suffix) { 'a_suffix' }

      # Based on the 3 lets defined above
      let(:encoded_key) do
        key_to_flush_prefix +
            report_key_prefix
            "service_id:#{service_id}," +
            credentials.to_sorted_escaped_s +
            suffix
      end

      context 'when the key contains just one credential' do
        let(:credentials) do
          Credentials.new(user_key: 'a,user:key') # ':' and ',' need to be escaped
        end

        it 'returns an array with the service ID and credentials encoded in the key' do
          expect(subject.service_and_creds(encoded_key, suffix))
              .to eq [service_id, credentials]
        end
      end

      context 'when the key contains several credentials' do
        let(:credentials) do
          Credentials.new(app_id: 'an,app:id', app_key: 'a_key')
        end

        it 'returns an array with the service ID and credentials encoded in the key' do
          expect(subject.service_and_creds(encoded_key, suffix))
              .to eq [service_id, credentials]
        end
      end
    end

    describe '.name_key_to_flush' do
      let(:report_key) { 'a_report_key' }
      let(:suffix) { 'a_suffix' }

      it 'returns the name of a key marked as to be flushed with the expected format' do
        expected = "#{key_to_flush_prefix}#{report_key}#{suffix}"
        actual = subject.name_key_to_flush(report_key, suffix)

        expect(actual).to eq expected
      end
    end
  end
end
