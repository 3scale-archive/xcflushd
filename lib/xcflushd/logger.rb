require 'logger'

module Xcflushd
  class Logger
    def self.new(*args)
      # Logging to a IO-like object.
      #
      # When the IO object is a TTY, Ruby sets line buffered mode, which is
      # ok for logs. However, when it is not a TTY, Ruby sets up a buffer
      # of unspecified size that causes applications that write few logs to
      # appear as inactive in the log stream. This is a problem when trying
      # to diagnose issues.
      #
      # Unfortunately Ruby only exposes a couple of limited ways to control
      # the underlying buffering: IO#(f)sync and IO#flush. Apparently the C
      # runtime stdio buffering is replaced by Ruby's own, so there is no
      # point in trying to call setvbuf, and no point either in trying to
      # control a TTY, since that case is fine.
      #
      # Since our logging stream activity is fairly low it's reasonable to
      # use IO#sync for the non TTY case to have (hopefully) a behaviour
      # similar to line-buffered standard I/O.
      #
      # More info on http://tuxdna.in/files/notes/ruby-io.html.
      #
      io = args[0]
      io.sync = true unless io.tty?
      ::Logger.new(*args)
    end
  end
end
