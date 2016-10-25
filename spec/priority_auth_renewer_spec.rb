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
    let(:logger) { double('logger', warn: true, error: true) }
    let(:storage) { Storage.new(redis_storage, logger) }
    let(:redis_pub) { Redis.new }
    let(:redis_sub) { Redis.new }
    let(:auth_valid_min) { 10 }

    subject do
      described_class.new(
          authorizer, storage, redis_pub, redis_sub, auth_valid_min, logger)
    end

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
      { 'metric2' => Authorization.ok!, 'metric3' => Authorization.ok! }
    end
    let(:authorizations) { metric_auth.merge(other_app_metrics_auths) }

    before do
      # We need to wait in the code, but not here in the tests.
      allow_any_instance_of(Object).to receive(:sleep)

      redis_pub.publish(auth_requests_channel, requests_channel_msg)
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
        other_app_metrics_auths.each do |other_metric, other_auth|
          cached_auth = redis_storage.hget(
              "auth:#{service_id}:#{user_key}", other_metric)
          expect(cached_auth).to eq(other_auth.authorized? ? '1' : '0')
        end
      end

      it 'removes the authorization processed from the list of current ones' do
        expect(subject.send(:current_auths)).to be_empty
      end
    end

    context 'when the message is processed correctly' do
      before do
        allow(authorizer)
            .to receive(:authorizations)
            .with(service_id, user_key, [metric])
            .and_return(authorizations)

        subject.start

        # When the renewer receives a message, it renews the authorizations and
        # publishes them asynchronously. For these tests, we need to force the
        # execution and block until all the async tasks are finished.
        # shutdown processes the pending tasks and stops accepting more.
        subject.send(:thread_pool).shutdown
        subject.send(:thread_pool).wait_for_termination
      end

      context 'and the metric received is authorized' do
        let(:metric_auth) { { metric => Authorization.ok! } }
        include_examples 'authorization to be renewed', '1'
      end

      context 'and the metric received is not authorized' do
        context 'and the deny reason is specified' do
          let(:metric_auth) { { metric => Authorization.denied!('a_reason') } }
          include_examples 'authorization to be renewed', '0:a_reason'
        end

        context 'and the deny reason is not specified' do
          let(:metric_auth) { { metric => Authorization.denied! } }
          include_examples 'authorization to be renewed', '0'
        end
      end
    end

    context 'when processing the message fails' do
      before do
        allow(subject)
            .to receive(:async_renew_and_publish_task)
            .and_raise(StandardError.new)

        subject.start
        subject.send(:thread_pool).shutdown
        subject.send(:thread_pool).wait_for_termination
      end

      it 'logs an error' do
        expect(logger).to have_received(:error)
      end
    end

    context 'when there is an error in the renew and publish task' do
      before do
        allow(authorizer).to receive(:authorizations).and_raise

        subject.start
        subject.send(:thread_pool).shutdown
        subject.send(:thread_pool).wait_for_termination
      end

      it 'removes the authorization processed from the list of current ones' do
        expect(subject.send(:current_auths)).to be_empty
      end
    end

    context 'when subscribing to the requests channel fails' do
      before do
        allow(subject).to receive(:subscribe_to_requests_channel).and_raise
      end

      it 'aborts' do
        expect { subject.start }
            .to raise_exception(SystemExit)
            .and output.to_stderr # Do not show the msg when running the tests
      end
    end

    context 'when there is an error publishing the response' do
      let(:metric_auth) { { metric => Authorization.ok! } }

      before do
        allow(redis_pub).to receive(:publish).and_raise

        allow(authorizer)
            .to receive(:authorizations)
            .with(service_id, user_key, [metric])
            .and_return(authorizations)
      end

      it 'logs a warning' do
        subject.start
        subject.send(:thread_pool).shutdown
        subject.send(:thread_pool).wait_for_termination
        expect(logger).to have_received(:warn)
      end
    end
  end
end
