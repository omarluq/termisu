# POSIX poll-based event poller (fallback).
#
# Provides portable event handling using the POSIX poll() syscall
# with software-based timer implementation using monotonic clock.
require "../../time_compat"

#
# ## Features
#
# - Works on all POSIX-compliant systems
# - Software-based timers using Time.instant
# - Automatic timeout calculation for timer precision
#
# ## Timer Implementation
#
# Timers are tracked as monotonic clock deadlines. The poll timeout
# is calculated as the minimum of user timeout and next timer deadline.
# This provides reasonable timer precision (~1ms) on most systems.
#
# ## Trade-offs
#
# Less efficient than epoll/kqueue:
# - O(n) fd scanning vs O(1) for epoll
# - Software timers vs kernel timers
# - More syscalls when idle
#
# Use Linux or Kqueue backends when available.

# LibC poll bindings (not always provided by Crystal stdlib)
lib LibC
  struct Pollfd
    fd : Int32
    events : Short
    revents : Short
  end

  # nfds_t is unsigned long on Linux (64-bit on x86_64) but unsigned int
  # on Darwin/BSD. Use a platform-conditional alias for ABI correctness.
  {% if flag?(:linux) %}
    alias NfdsT = UInt64
  {% else %}
    alias NfdsT = UInt32
  {% end %}

  fun poll(fds : Pollfd*, nfds : NfdsT, timeout : Int32) : Int32

  POLLIN   = 0x0001_i16
  POLLPRI  = 0x0002_i16
  POLLOUT  = 0x0004_i16
  POLLERR  = 0x0008_i16
  POLLHUP  = 0x0010_i16
  POLLNVAL = 0x0020_i16
end

class Termisu::Event::Poller::Poll < Termisu::Event::Poller
  Log = Termisu::Logs::Event

  # Internal timer state using monotonic clock
  private struct TimerState
    getter interval : Time::Span
    getter next_deadline : MonotonicTime
    getter? repeating : Bool

    def initialize(@interval : Time::Span, @repeating : Bool)
      @next_deadline = monotonic_now + @interval
    end

    # Creates a new state with updated deadline
    def reset : TimerState
      TimerState.new(@interval, @repeating)
    end
  end

  @fds : Array(LibC::Pollfd)
  @timers : Hash(UInt64, TimerState)
  @next_timer_id : UInt64
  @closed : Bool

  def initialize
    @fds = [] of LibC::Pollfd
    @timers = {} of UInt64 => TimerState
    @next_timer_id = 0_u64
    @closed = false
    Log.debug { "Poll fallback poller created" }
  end

  def register_fd(fd : Int32, events : FDEvents) : Nil
    raise "Poller is closed" if @closed

    # Check if already registered and update
    # NOTE: Structs are value types - must replace the entire element
    existing_idx = @fds.index { |pfd| pfd.fd == fd }
    if existing_idx
      updated = @fds[existing_idx]
      updated.events = events_to_poll(events)
      @fds[existing_idx] = updated
    else
      pollfd = LibC::Pollfd.new
      pollfd.fd = fd
      pollfd.events = events_to_poll(events)
      pollfd.revents = 0
      @fds << pollfd
    end
    Log.debug { "Registered fd=#{fd} for events=#{events}" }
  end

  def unregister_fd(fd : Int32) : Nil
    return if @closed

    @fds.reject! { |pfd| pfd.fd == fd }
    Log.debug { "Unregistered fd=#{fd}" }
  end

  def add_timer(interval : Time::Span, repeating : Bool = true) : TimerHandle
    raise "Poller is closed" if @closed

    id = @next_timer_id
    @next_timer_id &+= 1
    @timers[id] = TimerState.new(interval, repeating)
    Log.debug { "Added timer id=#{id} interval=#{interval} repeating=#{repeating}" }
    TimerHandle.new(id)
  end

  def modify_timer(handle : TimerHandle, interval : Time::Span) : Nil
    raise "Poller is closed" if @closed

    state = @timers[handle.id]?
    unless state
      raise ArgumentError.new("Invalid timer handle: #{handle.id}")
    end

    @timers[handle.id] = TimerState.new(interval, state.repeating?)
    Log.debug { "Modified timer id=#{handle.id} new_interval=#{interval}" }
  end

  def remove_timer(handle : TimerHandle) : Nil
    return if @closed

    @timers.delete(handle.id)
    Log.debug { "Removed timer id=#{handle.id}" }
  end

  def wait : PollResult?
    wait_internal(nil)
  end

  def wait(timeout : Time::Span) : PollResult?
    wait_internal(timeout)
  end

  def close : Nil
    return if @closed
    @closed = true

    @fds.clear
    @timers.clear
    Log.debug { "Poll fallback poller closed" }
  end

  # Internal wait with optional timeout
  private def wait_internal(user_timeout : Time::Span?) : PollResult?
    return nil if @closed

    # Record deadline at method entry to honor user timeout across loop iterations
    deadline = user_timeout ? monotonic_now + user_timeout : nil

    loop do
      # Calculate effective timeout (factors in both deadline and timer deadlines)
      timeout_ms = calculate_timeout(deadline)

      # Check for ready events (timers or fds) before polling
      if ready = check_ready_events
        return ready
      end

      # Check if user deadline has passed
      return nil if deadline_expired?(deadline)

      # poll() syscall
      result = poll_with_eintr(timeout_ms)
      raise IO::Error.from_errno("poll") if result < 0

      # Check for ready events after poll
      if ready = check_ready_events
        return ready
      end

      # Check for timeout (no events, no timers, deadline passed)
      return nil if deadline_expired?(deadline)
      return nil if result == 0 && @timers.empty?

      # No events found, continue polling
      # This can happen if timeout was from timer calculation
      # but timer hasn't quite expired yet due to timing variance
    end
  end

  # Checks if the user-supplied deadline has expired
  private def deadline_expired?(deadline : MonotonicTime?) : Bool
    return false unless deadline
    monotonic_now >= deadline
  end

  # Checks for any ready events: expired timers first, then readable fds
  private def check_ready_events : PollResult?
    if timer_result = check_expired_timers
      return timer_result
    end
    check_fd_events
  end

  # Checks file descriptors for pending events from last poll() call
  private def check_fd_events : PollResult?
    @fds.each_with_index do |pfd, i|
      next if pfd.revents == 0
      type = poll_to_result_type(pfd.revents)
      # Struct is a value type — must write back to clear revents in the array
      cleared = pfd
      cleared.revents = 0
      @fds[i] = cleared
      return PollResult.new(type: type, fd: pfd.fd)
    end
    nil
  end

  # Calculates poll timeout based on timer deadlines and user deadline
  private def calculate_timeout(deadline : MonotonicTime?) : Int32
    timer_timeout = timer_timeout_ms

    # Calculate remaining time to user deadline
    user_ms = if deadline
                remaining = deadline - monotonic_now
                remaining.total_milliseconds.to_i.clamp(0, Int32::MAX)
              else
                nil
              end

    # Determine appropriate timeout based on timer and user timeout states
    if timer_timeout.nil? && user_ms.nil?
      # Both nil - infinite wait
      return -1
    end

    # At this point, at least one of timer_timeout or user_ms is non-nil
    if (u = user_ms).nil?
      timer_timeout.as(Int32)
    elsif (t = timer_timeout).nil?
      u
    else
      Math.min(t, u)
    end
  end

  # Returns timeout until next timer in milliseconds, or nil if no timers
  private def timer_timeout_ms : Int32?
    return nil if @timers.empty?

    now = monotonic_now
    min_timeout = Int32::MAX

    @timers.each_value do |state|
      remaining = state.next_deadline - now
      ms = remaining.total_milliseconds.to_i.clamp(0, Int32::MAX)
      min_timeout = ms if ms < min_timeout
    end

    min_timeout
  end

  # Checks for expired timers and returns result if found
  private def check_expired_timers : PollResult?
    return nil if @timers.empty?

    now = monotonic_now

    @timers.each do |id, state|
      next unless now >= state.next_deadline

      expirations = calculate_expirations(state, now)

      if state.repeating?
        @timers[id] = state.reset
      else
        @timers.delete(id)
      end

      return PollResult.new(
        type: PollResult::Type::Timer,
        timer_handle: TimerHandle.new(id),
        timer_expirations: expirations
      )
    end

    nil
  end

  # Calculates number of timer expirations (for missed ticks)
  private def calculate_expirations(state : TimerState, now : MonotonicTime) : UInt64
    return 1_u64 unless state.repeating?

    # How many intervals have passed since original deadline
    elapsed = now - (state.next_deadline - state.interval)
    (elapsed / state.interval).to_u64.clamp(1_u64, UInt64::MAX)
  end

  # Calls poll() with EINTR retry, respecting elapsed time so retries
  # do not extend the effective wait beyond the original timeout.
  private def poll_with_eintr(timeout_ms : Int32) : Int32
    remaining = timeout_ms
    loop do
      start = monotonic_now
      result = LibC.poll(@fds.to_unsafe, LibC::NfdsT.new(@fds.size), remaining)
      if result < 0 && Errno.value == Errno::EINTR
        if remaining >= 0 # finite timeout — subtract elapsed time
          elapsed = (monotonic_now - start).total_milliseconds.to_i
          remaining -= elapsed
          return 0 if remaining <= 0 # timeout expired during retries
        end
        next
      end
      return result
    end
  end

  # Converts FDEvents to poll event mask
  private def events_to_poll(events : FDEvents) : Int16
    result = 0_i16
    result |= LibC::POLLIN if events.read?
    result |= LibC::POLLOUT if events.write?
    result
  end

  # Converts poll revents to PollResult::Type
  private def poll_to_result_type(revents : Int16) : PollResult::Type
    if (revents & (LibC::POLLERR | LibC::POLLNVAL)) != 0
      PollResult::Type::FDError
    elsif (revents & LibC::POLLHUP) != 0
      # Hangup - treat as error for consistency
      PollResult::Type::FDError
    elsif (revents & LibC::POLLOUT) != 0
      PollResult::Type::FDWritable
    elsif (revents & LibC::POLLIN) != 0
      PollResult::Type::FDReadable
    else
      # Unknown event - treat as error
      PollResult::Type::FDError
    end
  end
end
