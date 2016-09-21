require 'spec_helper'

module Xcflushd
  # In these tests, we are using FakeRedis. The way the publish/subscribe
  # pattern works is a bit different. Normally, in our code, first we subscribe
  # to a channel and then, we receive the messages that someone else publishes
  # in that channel. When using FakeRedis, is is the other way around, to get
  # the messages, first we need to publish them and then subscribe to the same
  # channel. This is because the authors did not want to make the subscribe
  # method blocking.

  describe PriorityAuthRenewer do
    let(:authorizer) { double('authorizer') }
    let(:redis_storage) { Redis.new }
    let(:storage) { Storage.new(redis_storage) }
    let(:redis_pub) { Redis.new }
    let(:redis_sub) { Redis.new }
    let(:auth_valid_min) { 10 }

    let(:auth_requests_channel) do
      described_class.const_get(:AUTH_REQUESTS_CHANNEL)
    end

    let(:responses_channel_prefix) do
      described_class.const_get(:AUTH_RESPONSES_CHANNEL_PREFIX)
    end

    let(:service_id) { 'a_service_id' }
    let(:user_key) { 'a_user_key' }
    let(:metric) { 'a_metric' }

    let(:requests_channel_msg) { "#{service_id}:#{user_key}:#{metric}" }
    let(:responses_channel) do
      "#{responses_channel_prefix}#{requests_channel_msg}"
    end

    let(:other_app_metrics_auths) do
      [Authorization.new('metric2', true), Authorization.new('metric3', true)]
    end
    let(:authorizations) { metric_auth + other_app_metrics_auths }

    before do
      allow(authorizer)
          .to receive(:authorizations)
          .with(service_id, user_key, [metric])
          .and_return(authorizations)

      redis_pub.publish(auth_requests_channel, requests_channel_msg)

      renewer = described_class.new(
          authorizer, storage, redis_pub, redis_sub, auth_valid_min)

      # When the renewer receives a message, it renews the authorizations and
      # publishes them asynchronously. For these tests, we need to force the
      # execution and block until all the async tasks are finished.
      # shutdown processes the pending tasks and stops accepting more.
      renewer.send(:thread_pool).shutdown
      renewer.send(:thread_pool).wait_for_termination
    end

    shared_examples 'authorization to be renewed' do |auth|
      it 'renews its cached authorization' do
        cached_auth = redis_storage.hget(
            "auth:#{service_id}:#{user_key}", metric)
        expect(cached_auth).to eq auth
      end

      it 'publishes the authorization status to the appropriate channel' do
        redis_sub.subscribe(responses_channel) do |on|
          on.message { |_channel, msg| expect(msg).to eq auth }
        end
      end

      it 'renews the auth for all the limited metrics of the app' do
        other_app_metrics_auths.each do |metric_auth|
          cached_auth = redis_storage.hget(
              "auth:#{service_id}:#{user_key}", metric_auth.metric)
          expect(cached_auth).to eq(metric_auth.authorized? ? '1' : '0')
        end
      end
    end

    context 'when the metric received is authorized' do
      let(:metric_auth) { [Authorization.new(metric, true)] }
      include_examples 'authorization to be renewed', '1'
    end

    context 'when the metric received is not authorized' do
      context 'and the deny reason is specified' do
        let(:metric_auth) { [Authorization.new(metric, false, 'disabled')] }
        include_examples 'authorization to be renewed', '0:disabled'
      end

      context 'and the deny reason is not specified' do
        let(:metric_auth) { [Authorization.new(metric, false)] }
        include_examples 'authorization to be renewed', '0'
      end
    end
  end
end
