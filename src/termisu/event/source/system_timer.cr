# System timer event source using kernel-level timing.
#
# Uses the platform-specific Poller for high-precision timer events:
# - Linux: timerfd with epoll
# - macOS/BSD: kqueue EVFILT_TIMER
# - Fallback: monotonic clock with poll
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
  @start_time : Time::Instant?
  @last_tick : Time::Instant?
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
    @start_time = Time.instant
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
  # Uses short poll timeouts with Fiber.yield to cooperate with
  # Crystal's fiber scheduler, allowing other fibers (like Input)
  # to run between timer checks.
  private def run_loop : Nil
    output = @output
    poller = @poller
    start_time = @start_time
    last_tick = @last_tick
    return unless output && poller && start_time && last_tick

    current_last_tick = last_tick

    while @running.get
      # Yield to allow other fibers (like Input) to run before blocking on poller.
      # This is important for fiber scheduler cooperation - without it, the timer
      # fiber could monopolize CPU time on systems with high timer frequency.
      Fiber.yield

      # Wait for timer event with no timeout - timer already registered via add_timer.
      # Passing @interval here would create a "double timeout" situation where both
      # the kernel timer (timerfd/kqueue) and poller timeout trigger at ~same time.
      result = poller.wait

      # Check running state after wait (may have been stopped)
      break unless @running.get

      # No event this cycle - loop back
      next unless result

      case result.type
      when .timer?
        now = Time.instant
        elapsed = now - start_time
        delta = now - current_last_tick
        frame = @frame

        # Calculate missed ticks from expiration count
        # Expirations > 1 means we missed some timer fires
        missed = result.timer_expirations > 0 ? result.timer_expirations - 1 : 0_u64

        tick = Event::Tick.new(
          elapsed: elapsed,
          delta: delta,
          frame: frame,
          missed_ticks: missed,
        )

        current_last_tick = now
        @last_tick = now
        @frame += 1

        output.send(tick)

        if missed > 0
          Log.warn { "SystemTimer missed #{missed} tick(s) at frame #{frame}" }
        end
      end
    end
  rescue Channel::ClosedError
    Log.debug { "SystemTimer channel closed, exiting" }
  end
end
