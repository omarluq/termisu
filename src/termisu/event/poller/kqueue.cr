# BSD/macOS event poller using kqueue.
#
# Provides unified event handling through the kqueue mechanism
# with native timer support via EVFILT_TIMER.
#
# ## Features
#
# - Native timer events (no separate timer fd needed)
# - Unified fd and timer handling in single syscall
# - Millisecond timer precision
# - Automatic timer rearming for periodic timers
#
# ## Timer Implementation
#
# Uses EVFILT_TIMER with millisecond precision. For one-shot timers,
# EV_ONESHOT flag automatically removes the event after firing.
# Timer data field returns expiration count for missed ticks.
#
# ## EINTR Handling
#
# All kevent calls retry on EINTR for signal interrupt handling.
{% if flag?(:darwin) || flag?(:freebsd) || flag?(:openbsd) %}
  {% if flag?(:darwin) %}
    require "c/sys/event"
  {% else %}
    require "../../lib_c/kqueue"
  {% end %}

  class Termisu::Event::Poller::Kqueue < Termisu::Event::Poller
    Log = Termisu::Logs::Event

    # Maximum events per kevent call
    private MAX_EVENTS = 16

    # Internal timer state tracking
    private struct TimerState
      getter ident : UInt64
      getter interval : Time::Span
      getter? repeating : Bool

      def initialize(@ident : UInt64, @interval : Time::Span, @repeating : Bool)
      end
    end

    @kq : Int32
    @timers : Hash(UInt64, TimerState)
    @registered_fds : Set(Int32)
    @next_timer_id : UInt64
    @closed : Bool

    def initialize
      @kq = LibC.kqueue
      if @kq < 0
        raise IO::Error.from_errno("kqueue")
      end
      @timers = {} of UInt64 => TimerState
      @registered_fds = Set(Int32).new
      @next_timer_id = 0_u64
      @closed = false
      Log.debug { "Kqueue poller created with kq=#{@kq}" }
    end

    def register_fd(fd : Int32, events : FDEvents) : Nil
      raise "Poller is closed" if @closed

      # If fd already registered, remove filters we no longer want.
      # Delete one-at-a-time with ignore_errors because the filter may
      # not exist — on FreeBSD batched deletes fail entirely if any
      # single filter is missing.
      if @registered_fds.includes?(fd)
        unless events.read?
          apply_changes([make_kevent(fd.to_u64, LibC::EVFILT_READ, LibC::EV_DELETE)], ignore_errors: true)
        end
        unless events.write?
          apply_changes([make_kevent(fd.to_u64, LibC::EVFILT_WRITE, LibC::EV_DELETE)], ignore_errors: true)
        end
      end

      # Add/update requested filters individually. EV_ADD on an
      # existing filter updates it in place without clearing pending
      # events. We apply one at a time because on FreeBSD batched
      # kevent calls fail entirely if any single change fails.
      if events.read?
        apply_changes([make_kevent(fd.to_u64, LibC::EVFILT_READ, LibC::EV_ADD)])
      end
      if events.write?
        apply_changes([make_kevent(fd.to_u64, LibC::EVFILT_WRITE, LibC::EV_ADD)])
      end
      @registered_fds << fd
      Log.debug { "Registered fd=#{fd} for events=#{events}" }
    end

    def unregister_fd(fd : Int32) : Nil
      return if @closed
      return unless @registered_fds.delete(fd)

      changes = [
        make_kevent(fd.to_u64, LibC::EVFILT_READ, LibC::EV_DELETE),
        make_kevent(fd.to_u64, LibC::EVFILT_WRITE, LibC::EV_DELETE),
      ]

      apply_changes(changes, ignore_errors: true)
      Log.debug { "Unregistered fd=#{fd}" }
    end

    def add_timer(interval : Time::Span, repeating : Bool = true) : TimerHandle
      raise "Poller is closed" if @closed

      id = @next_timer_id
      @next_timer_id &+= 1

      ms = interval.total_milliseconds.to_i64

      flags = LibC::EV_ADD
      flags |= LibC::EV_ONESHOT unless repeating

      change = make_kevent(id, LibC::EVFILT_TIMER, flags)
      change.data = ms

      apply_changes([change])

      @timers[id] = TimerState.new(id, interval, repeating)
      Log.debug { "Added timer id=#{id} interval=#{interval} repeating=#{repeating}" }
      TimerHandle.new(id)
    end

    def modify_timer(handle : TimerHandle, interval : Time::Span) : Nil
      raise "Poller is closed" if @closed

      state = @timers[handle.id]?
      unless state
        raise ArgumentError.new("Invalid timer handle: #{handle.id}")
      end

      ms = interval.total_milliseconds.to_i64
      flags = LibC::EV_ADD
      flags |= LibC::EV_ONESHOT unless state.repeating?

      change = make_kevent(state.ident, LibC::EVFILT_TIMER, flags)
      change.data = ms

      apply_changes([change])
      @timers[handle.id] = TimerState.new(state.ident, interval, state.repeating?)
      Log.debug { "Modified timer id=#{handle.id} new_interval=#{interval}" }
    end

    def remove_timer(handle : TimerHandle) : Nil
      return if @closed

      state = @timers.delete(handle.id)
      return unless state

      change = make_kevent(state.ident, LibC::EVFILT_TIMER, LibC::EV_DELETE)
      apply_changes([change], ignore_errors: true)
      Log.debug { "Removed timer id=#{handle.id}" }
    end

    def wait : PollResult?
      wait_internal(nil)
    end

    def wait(timeout : Time::Span) : PollResult?
      ts = LibC::Timespec.new
      ts.tv_sec = timeout.total_seconds.to_i64
      ts.tv_nsec = ((timeout.total_nanoseconds - ts.tv_sec * 1_000_000_000).to_i64).clamp(0_i64, 999_999_999_i64)
      wait_internal(pointerof(ts))
    end

    def close : Nil
      return if @closed
      @closed = true

      @timers.clear
      @registered_fds.clear
      LibC.close(@kq)
      Log.debug { "Kqueue poller closed" }
    end

    # Internal wait with optional timeout (blocking when nil)
    private def wait_internal(timeout : Nil) : PollResult?
      return nil if @closed

      events = uninitialized LibC::Kevent[MAX_EVENTS]

      loop do
        n = LibC.kevent(@kq, nil, 0, events.to_unsafe, MAX_EVENTS, nil)

        if n < 0
          if Errno.value == Errno::EINTR
            next
          end
          raise IO::Error.from_errno("kevent wait")
        end

        return nil if n == 0 # Unexpected: kevent should not return 0 with NULL timeout

        event = events[0]

        case event.filter
        when LibC::EVFILT_TIMER
          expirations = event.data.to_u64
          expirations = 1_u64 if expirations == 0
          return PollResult.new(
            type: PollResult::Type::Timer,
            timer_handle: TimerHandle.new(event.ident.to_u64),
            timer_expirations: expirations
          )
        when LibC::EVFILT_READ
          return PollResult.new(type: PollResult::Type::FDReadable, fd: event.ident.to_i32)
        when LibC::EVFILT_WRITE
          return PollResult.new(type: PollResult::Type::FDWritable, fd: event.ident.to_i32)
        else
          # Includes EVFILT_SIGNAL and error conditions
          return PollResult.new(type: PollResult::Type::FDError, fd: event.ident.to_i32)
        end
      end
    end

    private def wait_internal(timeout : LibC::Timespec*) : PollResult?
      return nil if @closed

      events = uninitialized LibC::Kevent[MAX_EVENTS]

      loop do
        n = LibC.kevent(@kq, nil, 0, events.to_unsafe, MAX_EVENTS, timeout)

        if n < 0
          if Errno.value == Errno::EINTR
            next
          end
          raise IO::Error.from_errno("kevent wait")
        end

        return nil if n == 0 # Timeout

        event = events[0]

        case event.filter
        when LibC::EVFILT_TIMER
          expirations = event.data.to_u64
          expirations = 1_u64 if expirations == 0
          return PollResult.new(
            type: PollResult::Type::Timer,
            timer_handle: TimerHandle.new(event.ident.to_u64),
            timer_expirations: expirations
          )
        when LibC::EVFILT_READ
          return PollResult.new(type: PollResult::Type::FDReadable, fd: event.ident.to_i32)
        when LibC::EVFILT_WRITE
          return PollResult.new(type: PollResult::Type::FDWritable, fd: event.ident.to_i32)
        else
          # Includes EVFILT_SIGNAL and error conditions
          return PollResult.new(type: PollResult::Type::FDError, fd: event.ident.to_i32)
        end
      end
    end

    # Creates a kevent struct with the given parameters
    private def make_kevent(ident : UInt64, filter : Int16, flags : UInt16) : LibC::Kevent
      event = LibC::Kevent.new
      event.ident = ident
      event.filter = filter
      event.flags = flags
      event.fflags = 0_u32
      event.data = 0
      event.udata = Pointer(Void).null
      event
    end

    # Applies kevent changes with EINTR retry
    private def apply_changes(changes : Array(LibC::Kevent), ignore_errors : Bool = false) : Nil
      return if changes.empty?

      loop do
        result = LibC.kevent(@kq, changes.to_unsafe, changes.size, nil, 0, nil)
        if result < 0
          if Errno.value == Errno::EINTR
            next
          end
          raise IO::Error.from_errno("kevent apply") unless ignore_errors
        end
        return
      end
    end
  end
{% end %}
