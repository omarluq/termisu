# Linux event poller using epoll + timerfd.
#
# Provides high-precision timer events and efficient I/O multiplexing
# through the Linux kernel's epoll and timerfd subsystems.
#
# ## Features
#
# - Kernel-level timer precision (<1ms accuracy)
# - O(1) event notification via epoll
# - Automatic timer rearming for periodic timers
# - Missed tick detection via expiration count
#
# ## Timer Implementation
#
# Uses `timerfd_create` with `CLOCK_MONOTONIC` for drift-free timing.
# Periodic timers use `it_interval` for automatic rearming.
# The timerfd is added to epoll for unified event handling.
#
# ## EINTR Handling
#
# All syscalls retry on EINTR to handle signal interrupts gracefully.
{% if flag?(:linux) %}
  require "c/sys/timerfd"
  require "c/sys/epoll"

  class Termisu::Event::Poller::Linux < Termisu::Event::Poller
    Log = Termisu::Logs::Event

    # Maximum events per epoll_wait call
    private MAX_EVENTS = 16

    # Internal timer state tracking
    private struct TimerState
      getter fd : Int32
      getter interval : Time::Span
      getter? repeating : Bool

      def initialize(@fd : Int32, @interval : Time::Span, @repeating : Bool)
      end
    end

    @epoll_fd : Int32
    @timers : Hash(UInt64, TimerState)
    @fd_to_timer : Hash(Int32, UInt64)
    @next_timer_id : UInt64
    @closed : Bool

    def initialize
      @epoll_fd = LibC.epoll_create1(LibC::EPOLL_CLOEXEC)
      if @epoll_fd < 0
        raise IO::Error.from_errno("epoll_create1")
      end
      @timers = {} of UInt64 => TimerState
      @fd_to_timer = {} of Int32 => UInt64
      @next_timer_id = 0_u64
      @closed = false
      Log.debug { "Linux poller created with epoll_fd=#{@epoll_fd}" }
    end

    def register_fd(fd : Int32, events : FDEvents) : Nil
      raise "Poller is closed" if @closed

      event = LibC::EpollEvent.new
      event.events = events_to_epoll(events)
      event.data.fd = fd

      result = epoll_ctl_retry(LibC::EPOLL_CTL_ADD, fd, pointerof(event))
      if result < 0
        raise IO::Error.from_errno("epoll_ctl ADD fd=#{fd}")
      end
      Log.debug { "Registered fd=#{fd} for events=#{events}" }
    end

    def unregister_fd(fd : Int32) : Nil
      return if @closed

      result = epoll_ctl_retry(LibC::EPOLL_CTL_DEL, fd, nil)
      # Ignore ENOENT - fd was already removed or never registered
      if result < 0 && Errno.value != Errno::ENOENT
        raise IO::Error.from_errno("epoll_ctl DEL fd=#{fd}")
      end
      Log.debug { "Unregistered fd=#{fd}" }
    end

    def add_timer(interval : Time::Span, repeating : Bool = true) : TimerHandle
      raise "Poller is closed" if @closed

      fd = LibC.timerfd_create(LibC::CLOCK_MONOTONIC, LibC::TFD_NONBLOCK | LibC::TFD_CLOEXEC)
      if fd < 0
        raise IO::Error.from_errno("timerfd_create")
      end

      begin
        arm_timerfd(fd, interval, repeating)

        event = LibC::EpollEvent.new
        event.events = LibC::EPOLLIN
        event.data.fd = fd

        result = epoll_ctl_retry(LibC::EPOLL_CTL_ADD, fd, pointerof(event))
        if result < 0
          raise IO::Error.from_errno("epoll_ctl ADD timerfd")
        end

        id = @next_timer_id
        @next_timer_id &+= 1
        @timers[id] = TimerState.new(fd, interval, repeating)
        @fd_to_timer[fd] = id

        Log.debug { "Added timer id=#{id} fd=#{fd} interval=#{interval} repeating=#{repeating}" }
        TimerHandle.new(id)
      rescue ex
        LibC.close(fd)
        raise ex
      end
    end

    def modify_timer(handle : TimerHandle, interval : Time::Span) : Nil
      raise "Poller is closed" if @closed

      state = @timers[handle.id]?
      unless state
        raise ArgumentError.new("Invalid timer handle: #{handle.id}")
      end

      arm_timerfd(state.fd, interval, state.repeating?)
      @timers[handle.id] = TimerState.new(state.fd, interval, state.repeating?)
      Log.debug { "Modified timer id=#{handle.id} new_interval=#{interval}" }
    end

    def remove_timer(handle : TimerHandle) : Nil
      return if @closed

      state = @timers.delete(handle.id)
      return unless state

      @fd_to_timer.delete(state.fd)
      epoll_ctl_retry(LibC::EPOLL_CTL_DEL, state.fd, nil)
      LibC.close(state.fd)
      Log.debug { "Removed timer id=#{handle.id}" }
    end

    def wait : PollResult?
      wait_internal(-1)
    end

    def wait(timeout : Time::Span) : PollResult?
      wait_internal(timeout.total_milliseconds.to_i)
    end

    def close : Nil
      return if @closed
      @closed = true

      @timers.each_value do |state|
        LibC.close(state.fd)
      end
      @timers.clear
      @fd_to_timer.clear

      LibC.close(@epoll_fd)
      Log.debug { "Linux poller closed" }
    end

    # Internal wait implementation with timeout in milliseconds
    private def wait_internal(timeout_ms : Int32) : PollResult?
      return nil if @closed

      events = uninitialized LibC::EpollEvent[MAX_EVENTS]

      loop do
        n = LibC.epoll_wait(@epoll_fd, events.to_unsafe, MAX_EVENTS, timeout_ms)

        if n < 0
          err = Errno.value
          if err == Errno::EINTR
            next # Retry on signal interrupt
          end
          raise IO::Error.from_errno("epoll_wait")
        end

        return nil if n == 0 # Timeout

        # Process first event
        event = events[0]
        fd = event.data.fd

        if timer_id = @fd_to_timer[fd]?
          expirations = read_timerfd(fd)
          return PollResult.new(
            type: PollResult::Type::Timer,
            timer_handle: TimerHandle.new(timer_id),
            timer_expirations: expirations
          )
        else
          type = epoll_to_result_type(event.events)
          return PollResult.new(type: type, fd: fd)
        end
      end
    end

    # Arms timerfd with interval supporting both one-shot and periodic modes
    private def arm_timerfd(fd : Int32, interval : Time::Span, repeating : Bool) : Nil
      spec = LibC::Itimerspec.new

      secs = interval.total_seconds.to_i64
      nsecs = ((interval.total_nanoseconds - secs * 1_000_000_000).to_i64).clamp(0_i64, 999_999_999_i64)

      spec.it_value.tv_sec = LibC::TimeT.new(secs)
      spec.it_value.tv_nsec = nsecs

      if repeating
        spec.it_interval.tv_sec = LibC::TimeT.new(secs)
        spec.it_interval.tv_nsec = nsecs
      else
        spec.it_interval.tv_sec = LibC::TimeT.new(0)
        spec.it_interval.tv_nsec = 0_i64
      end

      # flags = 0 means relative time (not TFD_TIMER_ABSTIME)
      loop do
        result = LibC.timerfd_settime(fd, 0, pointerof(spec), nil)
        if result < 0
          if Errno.value == Errno::EINTR
            next
          end
          raise IO::Error.from_errno("timerfd_settime")
        end
        return
      end
    end

    # Reads timerfd to acknowledge expiration and get count
    private def read_timerfd(fd : Int32) : UInt64
      expirations = 0_u64
      loop do
        bytes_read = LibC.read(fd, pointerof(expirations).as(Void*), sizeof(UInt64))
        if bytes_read < 0
          err = Errno.value
          if err == Errno::EINTR
            next
          elsif err == Errno::EAGAIN
            return 0_u64
          end
          raise IO::Error.from_errno("read timerfd")
        end
        return expirations
      end
    end

    # Wraps epoll_ctl with EINTR retry
    private def epoll_ctl_retry(op : Int32, fd : Int32, event : LibC::EpollEvent*?) : Int32
      loop do
        result = LibC.epoll_ctl(@epoll_fd, op, fd, event)
        if result < 0 && Errno.value == Errno::EINTR
          next
        end
        return result
      end
    end

    # Converts FDEvents to epoll event mask
    private def events_to_epoll(events : FDEvents) : UInt32
      result = 0_u32
      result |= LibC::EPOLLIN if events.read?
      result |= LibC::EPOLLOUT if events.write?
      result |= LibC::EPOLLERR if events.error?
      result
    end

    # Converts epoll event mask to PollResult::Type
    private def epoll_to_result_type(events : UInt32) : PollResult::Type
      if events.bits_set?(LibC::EPOLLERR)
        PollResult::Type::FDError
      elsif events.bits_set?(LibC::EPOLLOUT)
        PollResult::Type::FDWritable
      else
        PollResult::Type::FDReadable
      end
    end
  end
{% end %}
