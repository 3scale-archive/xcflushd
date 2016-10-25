require 'spec_helper'

module Xcflushd
  describe Authorization do
    describe '#authorized?' do
      context 'when authorized' do
        subject { Authorization.ok! }

        it 'returns true' do
          expect(subject.authorized?).to be true
        end
      end

      context 'when not authorized' do
        subject { Authorization.denied! }

        it 'returns false' do
          expect(subject.authorized?).to be false
        end
      end
    end

    describe '#reason' do
      context 'when specified' do
        subject { Authorization.denied!(reason) }
        let(:reason) { 'a_reason' }

        it 'returns the reason' do
          expect(subject.reason).to eq reason
        end
      end

      context 'when unspecified' do
        subject { Authorization.denied! }

        it 'returns nil' do
          expect(subject.reason).to be_nil
        end
      end
    end

    describe '#limits_exceeded?' do
      context 'when reason is limits exceeded' do
        subject { Authorization.denied!(Authorization.const_get(:LIMITS_EXCEEDED_CODE)) }

        it 'returns true' do
          expect(subject.limits_exceeded?).to be true
        end
      end

      context 'when reason is not limits exceeded' do
        subject { Authorization.denied!('some_reason') }

        it 'returns false' do
          expect(subject.limits_exceeded?).to be false
        end
      end
    end

    shared_examples_for 'a constant object' do |obj, method, *args|
      subject { obj }
      before { allow(subject).to receive(:allocate).and_call_original }

      it 'does not allocate a new object' do
        expect(subject).to_not receive(:allocate)
        subject.send(method, *args)
      end

      # the 'be' matcher below tests for object id equality
      it 'always returns the same constant object' do
        expect(subject.send(method, *args)).to be(subject.send(method, *args))
      end
    end

    shared_examples_for 'an authorization' do |status, obj, method, *args|
      auth_status = status ? 'authorized' : 'unauthorized'

      it 'quacks like an Authorization' do
        methods = Authorization.public_instance_methods(false)
        instance = obj.send(method, *args)

        instance_quacking = methods.map do |meth|
          method_obj = instance.method(meth)
          [meth, method_obj.parameters]
        end.sort
        auth_quacking = methods.map do |meth|
          method_obj = Authorization.public_instance_method(meth)
          [meth, method_obj.parameters]
        end.sort

        expect(instance_quacking).to contain_exactly(*auth_quacking)
      end

      it "returns an #{auth_status} status" do
        expect(obj.send(method, *args).authorized?).to be status
      end

      unless args.compact.empty?
        it 'returns a reason' do
          expect(obj.send(method, *args).reason).to eq(args.first)
        end
      end
    end

    describe '.ok!' do
      it_behaves_like 'an authorization', true, described_class, :ok!
      it_behaves_like 'a constant object', described_class, :ok!
    end

    describe '.denied!' do
      context 'when no reason is given' do
        it_behaves_like 'an authorization', false, described_class, :denied!
        it_behaves_like 'a constant object', described_class, :denied!
      end

      context 'when specified reason is the well-known limits_exceeded' do
        it_behaves_like 'an authorization', false, described_class, :denied!, 'limits_exceeded'
        it_behaves_like 'a constant object', described_class, :denied!, 'limits_exceeded'
      end

      context 'when specified reason is not well-known' do
        it_behaves_like 'an authorization', false, described_class, :denied!, 'some_reason'

        # allocation behaviour is unspecified when the cause is not well-known
      end
    end

    describe '.deny_over_limits' do
      it_behaves_like 'an authorization', false, described_class, :deny_over_limits
    end
  end
end
