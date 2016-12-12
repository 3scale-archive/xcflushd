require 'concurrent'

module Xcflushd
  describe Threading do
    describe '.default_values' do
      it 'returns a minimum of 0 threads' do
        expect(described_class.default_threads_value.min).to be_zero
      end

      it 'returns a maximum of at least the number of host processors' do
        expect(described_class.default_threads_value.max).
          to be >= Concurrent.processor_count
      end
    end
  end
end
