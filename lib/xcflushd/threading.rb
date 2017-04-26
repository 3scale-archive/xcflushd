# Helper for default threading values.
require 'concurrent'

module Xcflushd
  module Threading
    def self.default_threads
      Concurrent.processor_count * 4
    end
  end
end
