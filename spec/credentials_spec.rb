require 'spec_helper'
require 'xcflushd/credentials'

module Xcflushd
  describe Credentials do
    describe '#initialize' do
      let(:valid_attrs) { { app_id: 'ai', app_key: 'ak' } }

      context 'when it receives a hash with only valid attrs' do
        it 'creates an object with all of them' do
          creds = described_class.new(valid_attrs).creds
          expect(creds).to eq valid_attrs
        end
      end

      context 'when it receives a hash with attrs that are not valid' do
        let(:invalid_attrs) { { invalid: 'invalid' } }

        it 'discards the invalid ones' do
          creds = described_class.new(valid_attrs.merge(invalid_attrs)).creds
          expect(creds).to eq valid_attrs
        end
      end
    end

    describe '#to_sorted_escaped_s' do
      let(:creds) do
        { app_key: 'ak', referrer: 'r', app_id: 'a:i,1' }
      end

      # Based on creds.
      let(:creds_expected) do
        'app_id:a\\:i\\,1,app_key:ak,referrer:r'
      end

      it "returns a string with sorted creds separated by ',', and values separated by ':'" do
        expect(described_class.new(creds).to_sorted_escaped_s)
            .to eq creds_expected
      end
    end

    describe '#==' do
      context 'when comparing an object with itself' do
        let(:creds) { described_class.new(app_id: 'ai', app_key: 'ak') }

        it 'returns true' do
          expect(creds == creds).to be true
        end
      end

      context 'when the 2 objects are Credentials and have the same creds' do
        let(:creds1) { described_class.new(app_id: 'ai', app_key: 'ak') }
        let(:creds2) { described_class.new(app_id: 'ai', app_key: 'ak') }

        it 'returns true' do
          expect(creds1 == creds2).to be true
        end
      end

      context 'when the 2 objects are Credentials but they do not have the same creds' do
        let(:creds1) { described_class.new(app_id: 'ai', app_key: 'ak') }
        let(:creds2) { described_class.new(app_id: 'a1', user_key: 'uk') }

        it 'returns false' do
          expect(creds1 == creds2).to be false
        end
      end

      context 'when the 2 objects have the same creds, but one is not a Credentials object' do
        let(:creds1) { described_class.new(app_id: 'ai', app_key: 'ak') }
        let(:creds2) { double(creds: creds1.creds) }

        it 'returns false' do
          expect(creds1 == creds2).to be false
        end
      end
    end

    describe '.from' do
      let(:input_string) { 'app_id:a\\:i\\,1,app_key:ak,referrer:r' }

      # Based on input_string
      let(:expected_creds) { { app_id: 'a:i,1', app_key: 'ak', referrer: 'r' } }

      it 'creates a Credentials object from an escaped string with the defined format' do
        expect(described_class.from(input_string).creds).to eq expected_creds
      end
    end

    describe 'oauth?' do
      let(:subject) { described_class.new(creds) }

      context 'when credentials contain an access_token' do
        let(:creds) { { app_id: 'ai', access_token: 'at' } }

        it 'returns true' do
          expect(subject.oauth?).to be true
        end
      end

      context 'when credentials do not contain an access_token' do
        let(:creds) { { app_id: 'ai' } }

        it 'return false' do
          expect(subject.oauth?).to be false
        end
      end
    end
  end
end
