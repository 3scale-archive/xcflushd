require 'concurrent'

module Xcflushd
  describe Threading do
    describe '.default_threads' do
      it 'returns the number of host processors times 4' do
        expect(described_class.default_threads)
            .to eq Concurrent.processor_count * 4
      end
    end
  end
end
