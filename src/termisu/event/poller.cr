# Abstract base class for I/O event multiplexing.
#
# Provides unified interface for system-level event polling with support
# for file descriptor monitoring and high-precision timers.
#
# ## Platform Backends
#
# - **Linux**: epoll + timerfd for kernel-level timer precision
# - **macOS/BSD**: kqueue with EVFILT_TIMER
# - **Fallback**: POSIX poll with monotonic clock timers
#
# ## Usage
#
# ```
# poller = Termisu::Event::Poller.create
#
# # Register file descriptor for read events
# poller.register_fd(stdin_fd, FDEvents::Read)
#
# # Add a 16ms repeating timer (~60 FPS)
# timer = poller.add_timer(16.milliseconds)
#
# # Event loop
# loop do
#   case result = poller.wait
#   when nil
#     break # Shutdown
#   else
#     case result.type
#     when .timer?
#       handle_tick(result.timer_expirations)
#     when .fd_readable?
#       handle_input(result.fd)
#     end
#   end
# end
#
# poller.close
# ```
#
# ## Thread Safety
#
# Poller instances are NOT thread-safe. Use one poller per fiber/thread.
# File descriptor operations and timer management should occur on the
# same fiber that calls `wait`.
abstract class Termisu::Event::Poller
  # File descriptor event types for registration.
  @[Flags]
  enum FDEvents
    Read
    Write
    Error
  end

  # Opaque handle for timer identification.
  #
  # Used to modify or remove timers after creation.
  # The internal id is platform-specific.
  struct TimerHandle
    getter id : UInt64

    def initialize(@id : UInt64)
    end

    def ==(other : TimerHandle) : Bool
      @id == other.id
    end

    def hash(hasher)
      @id.hash(hasher)
    end
  end

  # Result of a poll wait operation.
  #
  # Contains the event type and associated data:
  # - For fd events: the file descriptor that triggered
  # - For timer events: the timer handle and expiration count
  struct PollResult
    # Type of event that occurred.
    enum Type
      FDReadable # File descriptor is readable
      FDWritable # File descriptor is writable
      FDError    # File descriptor has error condition
      Timer      # Timer expired
      Signal     # Signal received (platform-specific)
    end

    getter type : Type
    getter fd : Int32
    getter timer_handle : TimerHandle?
    getter timer_expirations : UInt64

    def initialize(
      @type : Type,
      @fd : Int32 = -1,
      @timer_handle : TimerHandle? = nil,
      @timer_expirations : UInt64 = 0_u64,
    )
    end

    # Returns true if this is a timer event.
    def timer? : Bool
      @type.timer?
    end

    # Returns true if this is an fd readable event.
    def fd_readable? : Bool
      @type.fd_readable?
    end

    # Returns true if this is an fd writable event.
    def fd_writable? : Bool
      @type.fd_writable?
    end

    # Returns true if this is an fd error event.
    def fd_error? : Bool
      @type.fd_error?
    end

    # Returns true if this is a signal event.
    def signal? : Bool
      @type.signal?
    end
  end

  # Registers a file descriptor for event monitoring.
  #
  # - `fd` - File descriptor to monitor
  # - `events` - Event types to monitor (read, write, error)
  #
  # Raises `IO::Error` on system error.
  abstract def register_fd(fd : Int32, events : FDEvents) : Nil

  # Unregisters a file descriptor from event monitoring.
  #
  # Safe to call with unregistered fd (no-op).
  abstract def unregister_fd(fd : Int32) : Nil

  # Creates a new timer with the specified interval.
  #
  # - `interval` - Time between timer expirations
  # - `repeating` - If true, timer auto-rearms; if false, fires once
  #
  # Returns a `TimerHandle` for later modification or removal.
  # Raises `IO::Error` on system error.
  abstract def add_timer(interval : Time::Span, repeating : Bool = true) : TimerHandle

  # Modifies an existing timer's interval.
  #
  # - `handle` - Timer to modify
  # - `interval` - New interval
  #
  # Raises `ArgumentError` if handle is invalid.
  abstract def modify_timer(handle : TimerHandle, interval : Time::Span) : Nil

  # Removes a timer.
  #
  # Safe to call with already-removed handle (no-op).
  abstract def remove_timer(handle : TimerHandle) : Nil

  # Waits indefinitely for an event.
  #
  # Blocks until an event occurs. Returns `nil` if the poller
  # is closed or interrupted in a way that signals shutdown.
  #
  # Handles EINTR internally by retrying.
  abstract def wait : PollResult?

  # Waits for an event with timeout.
  #
  # Returns `nil` if timeout expires without an event.
  # Handles EINTR internally by retrying.
  abstract def wait(timeout : Time::Span) : PollResult?

  # Releases all resources held by the poller.
  #
  # Closes internal file descriptors and clears timer state.
  # Safe to call multiple times (idempotent).
  abstract def close : Nil

  # Creates the optimal poller for the current platform.
  #
  # Returns:
  # - `Poller::Linux` on Linux (epoll + timerfd)
  # - `Poller::Kqueue` on macOS/FreeBSD/OpenBSD
  # - `Poller::Poll` as fallback
  def self.create : Poller
    {% if flag?(:linux) %}
      Poller::Linux.new
    {% elsif flag?(:darwin) || flag?(:freebsd) || flag?(:openbsd) %}
      Poller::Kqueue.new
    {% else %}
      Poller::Poll.new
    {% end %}
  end
end

# Load platform-specific implementations
require "./poller/*"
