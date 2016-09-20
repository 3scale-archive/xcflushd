require 'spec_helper'

module Xcflushd
  describe Authorization do
    describe '#authorized?' do
      it 'returns true when authorized' do
        auth = Authorization.new('a_metric', true)
        expect(auth.authorized?).to be true
      end

      it 'returns false when denied' do
        auth = Authorization.new('a_metric', false)
        expect(auth.authorized?).to be false
      end
    end
  end
end
