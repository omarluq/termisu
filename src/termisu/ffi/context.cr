class Termisu::FFI::Context
  getter termisu : ::Termisu

  # Bound the time an FFI poll waits before observing cross-thread shutdown.
  # Crystal channels are scheduler-local in supported non-preview_mt builds,
  # while atomics and OS sleeps work from arbitrary host threads.
  POLL_CANCELLATION_INTERVAL = 1.millisecond

  @closing = Atomic(Bool).new(false)
  @closed = Atomic(Bool).new(false)
  @in_flight = Atomic(Int32).new(0)

  def initialize(sync_updates : Bool)
    @scheduler_thread = Thread.current
    @termisu = ::Termisu.new(sync_updates: sync_updates)
  end

  # Runs one FFI operation while preventing close from crossing its lifetime.
  # The second closing check closes the race between the first check and the
  # counter increment: such a caller backs out without touching Termisu.
  def with_operation(& : self -> T) : T? forall T
    return nil if @closing.get

    @in_flight.add(1)
    if @closing.get
      @in_flight.sub(1)
      return nil
    end

    begin
      yield self
    ensure
      @in_flight.sub(1)
    end
  end

  # Polls non-blockingly between short OS sleeps so close can cancel an
  # indefinite (or very long) wait before draining operation leases. Avoiding
  # scheduler waits is required because the C ABI may run on a foreign thread.
  # The ownership lease remains held until close completes all cleanup below.
  def poll_event(timeout_ms : Int32) : Event::Any?
    return nil if @closing.get
    return @termisu.try_poll_event if timeout_ms == 0

    deadline = timeout_ms < 0 ? nil : monotonic_now + timeout_ms.milliseconds
    loop do
      return nil if @closing.get
      if event = @termisu.try_poll_event
        return event
      end

      wait = POLL_CANCELLATION_INTERVAL
      if deadline
        remaining = deadline - monotonic_now
        return nil if remaining <= 0.seconds
        wait = remaining if remaining < wait
      end
      Fiber.yield if Thread.current == @scheduler_thread
      sleep_os_thread(wait)
    end
  end

  private def sleep_os_thread(duration : Time::Span) : Nil
    total_nanoseconds = duration.total_nanoseconds.to_i64
    request = uninitialized LibC::Timespec
    request.tv_sec = typeof(request.tv_sec).new(total_nanoseconds // 1_000_000_000)
    request.tv_nsec = typeof(request.tv_nsec).new(total_nanoseconds % 1_000_000_000)

    loop do
      return if LibC.nanosleep(pointerof(request), out remaining) == 0
      return unless Errno.value == Errno::EINTR
      request = remaining
    end
  end

  # Exposed for lifecycle coordination and focused concurrency assertions.
  def operations_in_flight? : Bool
    @in_flight.get > 0
  end

  def close : Nil
    unless @closing.compare_and_set(false, true)[1]
      until @closed.get
        Fiber.yield if Thread.current == @scheduler_thread
        Thread.yield
      end
      return
    end

    until @in_flight.get.zero?
      Fiber.yield if Thread.current == @scheduler_thread
      Thread.yield
    end
    begin
      @termisu.close
    ensure
      @closed.set(true)
    end
  end
end
