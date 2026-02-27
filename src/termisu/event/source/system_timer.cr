# System timer event source using kernel-level timing.
#
# Uses the platform-specific Poller for high-precision timer events:
# - Linux: timerfd with epoll
# - macOS/BSD: kqueue EVFILT_TIMER
# - Fallback: monotonic clock with poll
require "../../time_compat"

#
# ## Advantages over sleep-based Timer
#
# - Kernel schedules ticks at exact intervals regardless of processing time
# - `timer_expirations` detects missed ticks for frame drop compensation
# - More consistent frame times for smooth animations
#
# ## Usage
#
# ```
# timer = Termisu::Event::Source::SystemTimer.new(interval: 16.milliseconds)
# loop = Termisu::Event::Loop.new
# loop.add_source(timer)
# loop.start
#
# while event = loop.output.receive?
#   case event
#   when Termisu::Event::Tick
#     if event.missed_ticks > 0
#       # Compensate for dropped frames
#     end
#     render_frame(event.delta)
#   end
# end
# ```
class Termisu::Event::Source::SystemTimer < Termisu::Event::Source
  Log = Termisu::Logs::Event

  # Default tick interval (~60 FPS).
  DEFAULT_INTERVAL = 16.milliseconds

  @running : Atomic(Bool)
  @interval : Time::Span
  @output : Channel(Event::Any)?
  @fiber : Fiber?
  @poller : Event::Poller?
  @timer_handle : Event::Poller::TimerHandle?
  @start_time : MonotonicTime?
  @last_tick : MonotonicTime?
  @frame : UInt64

  # Creates a new system timer with the specified interval.
  #
  # - `interval` - Time between tick events (default: 16ms for ~60 FPS)
  def initialize(@interval : Time::Span = DEFAULT_INTERVAL)
    @running = Atomic(Bool).new(false)
    @frame = 0_u64
  end

  # Returns the current interval between ticks.
  def interval : Time::Span
    @interval
  end

  # Sets the interval between ticks.
  #
  # If the timer is running, updates the system timer's interval.
  def interval=(value : Time::Span)
    @interval = value
    if handle = @timer_handle
      @poller.try(&.modify_timer(handle, value))
    end
    Log.debug { "SystemTimer interval changed to #{value}" }
  end

  # Starts generating tick events to the output channel.
  #
  # Creates a platform-specific Poller and timer, then spawns a fiber
  # to wait on timer events and emit Tick events to the channel.
  def start(output : Channel(Event::Any)) : Nil
    return unless @running.compare_and_set(false, true)

    @output = output
    @frame = 0_u64
    @start_time = monotonic_now
    @last_tick = @start_time

    # Create platform-specific poller and timer
    poller = Event::Poller.create
    @poller = poller
    @timer_handle = poller.add_timer(@interval, repeating: true)

    @fiber = spawn(name: "termisu-system-timer") do
      run_loop
    end

    Log.debug { "SystemTimer started with interval=#{@interval} using #{poller.class.name}" }
  end

  # Stops generating tick events and releases resources.
  def stop : Nil
    return unless @running.compare_and_set(true, false)

    @poller.try(&.close)
    @poller = nil
    @timer_handle = nil

    Log.debug { "SystemTimer stopped" }
  end

  # Returns true if the timer is currently running.
  def running? : Bool
    @running.get
  end

  # Returns the source name for identification.
  def name : String
    "system-timer"
  end

  # Main timer loop - waits on poller for timer events.
  #
  # Yields before each blocking poll wait to keep cooperative scheduling fair.
  private def run_loop : Nil
    output = @output
    poller = @poller
    start_time = @start_time
    last_tick = @last_tick
    return unless output && poller && start_time && last_tick

    current_last_tick = last_tick
    pending_missed = 0_u64

    while @running.get
      result = wait_for_poll_result(poller)
      break unless @running.get

      timer_result = as_timer_result(result)
      next unless timer_result

      current_last_tick, pending_missed = emit_tick(
        output,
        start_time,
        current_last_tick,
        pending_missed,
        timer_result
      )
    end
  rescue Channel::ClosedError
    Log.debug { "SystemTimer channel closed, exiting" }
  rescue ex : IO::Error
    # Expected shutdown race: stop closes poller fds while this fiber may still be
    # blocked in poller.wait (epoll_wait/kevent/poll), which can raise EBADF.
    # If we're already stopping, treat this as graceful termination.
    if @running.get
      raise ex
    end
    Log.debug { "SystemTimer stopped during poll wait (#{ex.message}), exiting" }
  end

  # Sends without blocking. Returns true on success, false when channel is full.
  private def send_nonblocking(output : Channel(Event::Any), event : Event::Tick) : Bool
    select
    when output.send(event)
      true
    else
      false
    end
  end

  # Yields before blocking on poller.wait to keep other fibers responsive.
  private def wait_for_poll_result(poller : Event::Poller) : Event::Poller::PollResult?
    Fiber.yield
    # Timer is already registered via add_timer, so blocking wait is expected.
    poller.wait
  end

  # Returns only timer results, ignoring fd/timeout events.
  private def as_timer_result(result : Event::Poller::PollResult?) : Event::Poller::PollResult?
    return unless result
    return result if result.type.timer?

    nil
  end

  # Emits one Tick event for a timer result and returns updated state:
  # {next_last_tick, next_pending_missed}.
  private def emit_tick(
    output : Channel(Event::Any),
    start_time : MonotonicTime,
    current_last_tick : MonotonicTime,
    pending_missed : UInt64,
    result : Event::Poller::PollResult,
  ) : {MonotonicTime, UInt64}
    now = monotonic_now
    elapsed = now - start_time
    delta = now - current_last_tick
    frame = @frame
    missed = missed_ticks_for(result.timer_expirations, pending_missed)

    tick = Event::Tick.new(
      elapsed: elapsed,
      delta: delta,
      frame: frame,
      missed_ticks: missed,
    )

    @last_tick = now
    @frame += 1

    next_pending_missed = send_nonblocking(output, tick) ? 0_u64 : missed + 1_u64

    if missed > 0
      Log.warn { "SystemTimer missed #{missed} tick(s) at frame #{frame}" }
    end

    {now, next_pending_missed}
  end

  # Expirations > 1 means kernel observed dropped intervals.
  private def missed_ticks_for(timer_expirations : UInt64, pending_missed : UInt64) : UInt64
    base_missed = timer_expirations > 0 ? timer_expirations - 1 : 0_u64
    base_missed + pending_missed
  end
end
