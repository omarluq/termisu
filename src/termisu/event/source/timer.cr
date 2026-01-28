# Periodic timer event source.
#
# Generates `Event::Tick` events at a configurable interval for
# animations, game loops, and other time-based operations.
#
# ## Usage
#
# ```
# timer = Termisu::Event::Source::Timer.new(interval: 16.milliseconds)
# loop = Termisu::Event::Loop.new
# loop.add_source(timer)
# loop.start
#
# while event = loop.output.receive?
#   case event
#   when Termisu::Event::Tick
#     position += velocity * event.delta.total_seconds
#     puts "Frame #{event.frame}, elapsed: #{event.elapsed}"
#   end
# end
# ```
#
# ## Timing Behavior
#
# - Uses `Time.instant` for accurate, non-jumping timing
# - `elapsed` - Total time since timer started
# - `delta` - Time since previous tick (for frame-rate independent updates)
# - `frame` - Counter starting at 0, increments each tick
#
# ## Thread Safety
#
# Uses `Atomic(Bool)` for the running state. Safe to call `start`/`stop`
# from different fibers. The `interval=` setter is thread-safe.
class Termisu::Event::Source::Timer < Termisu::Event::Source
  Log = Termisu::Logs::Event

  # Default tick interval (~60 FPS).
  DEFAULT_INTERVAL = 16.milliseconds

  @running : Atomic(Bool)
  @interval : Time::Span
  @output : Channel(Event::Any)?
  @fiber : Fiber?
  @start_time : Time::Instant?
  @last_tick : Time::Instant?
  @frame : UInt64

  # Creates a new timer with the specified interval.
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
  # The new interval takes effect on the next tick.
  # Can be changed while the timer is running.
  def interval=(value : Time::Span)
    @interval = value
    Log.debug { "Timer interval changed to #{value}" }
  end

  # Starts generating tick events to the output channel.
  #
  # Spawns a fiber that sleeps for the interval and sends
  # `Event::Tick` events. The fiber continues until `stop` is called.
  #
  # Prevents double-start with `compare_and_set`.
  def start(output : Channel(Event::Any)) : Nil
    return unless @running.compare_and_set(false, true)

    @output = output
    @frame = 0_u64
    @start_time = Time.instant
    @last_tick = @start_time

    @fiber = spawn(name: "termisu-timer") do
      run_loop
    end

    Log.debug { "Timer started with interval=#{@interval}" }
  end

  # Stops generating tick events.
  #
  # Sets the running flag to false, causing the fiber to exit
  # on its next iteration. Uses compare_and_set for idempotent
  # stop operations - calling stop twice is safe.
  def stop : Nil
    return unless @running.compare_and_set(true, false)
    Log.debug { "Timer stopped" }
  end

  # Returns true if the timer is currently running.
  def running? : Bool
    @running.get
  end

  # Returns the source name for identification.
  def name : String
    "timer"
  end

  # Main timer loop - runs in a spawned fiber.
  #
  # Captures start_time and last_tick at loop entry to avoid
  # repeated nil checks. Uses local variable capture pattern
  # for clean, ameba-compliant code.
  private def run_loop : Nil
    output = @output
    start_time = @start_time
    last_tick = @last_tick
    return unless output && start_time && last_tick

    # Track last tick time locally for delta calculations
    current_last_tick = last_tick

    while @running.get
      sleep @interval

      # Check again after sleep in case we were stopped
      break unless @running.get

      now = Time.instant
      elapsed = now - start_time
      delta = now - current_last_tick
      frame = @frame

      tick = Event::Tick.new(
        elapsed: elapsed,
        delta: delta,
        frame: frame,
      )

      # Update both local and instance variables
      current_last_tick = now
      @last_tick = now
      @frame += 1

      output.send(tick)
    end
  rescue Channel::ClosedError
    # Channel closed during shutdown - exit gracefully
    Log.debug { "Timer channel closed, exiting" }
  end
end
