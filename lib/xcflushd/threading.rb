# Helper for default threading values.
require 'concurrent'

module Xcflushd
  module Threading
    def self.default_threads_value
      cpus = Concurrent.processor_count
      # default thread pool minimum is zero
      return 0, cpus * 4
    end
  end
end
