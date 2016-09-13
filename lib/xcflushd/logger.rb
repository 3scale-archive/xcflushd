require 'logger'

module Xcflushd
  class Logger
    def self.new(*args)
      ::Logger.new(*args)
    end
  end
end
