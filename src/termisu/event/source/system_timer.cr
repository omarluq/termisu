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

  private class IntervalChange
    getter interval : Time::Span
    getter result : Channel(Exception?)

    def initialize(@interval : Time::Span)
      @result = Channel(Exception?).new(1)
    end
  end

  private class Run
    getter token : UInt64
    getter output : Channel(Event::Any)
    getter wakeups : Channel(Nil)
    getter started : Channel(Exception?)
    getter done : Channel(Nil)
    getter interval_changes : Channel(IntervalChange)
    getter start_time : MonotonicTime
    property poller : Event::Poller?
    property timer_handle : Event::Poller::TimerHandle?
    property interval : Time::Span
    property wait_interval : Time::Span
    property next_deadline : MonotonicTime?
    property error : Exception?

    def initialize(
      @token : UInt64,
      @output : Channel(Event::Any),
      @interval : Time::Span,
      @start_time : MonotonicTime,
    )
      @wait_interval = @interval
      @wakeups = Channel(Nil).new(1)
      @started = Channel(Exception?).new(1)
      @done = Channel(Nil).new
      @interval_changes = Channel(IntervalChange).new(1)
    end
  end

  @running : Atomic(Bool)
  @interval : Time::Span
  @run_token : Atomic(UInt64)
  @lifecycle_lock : Mutex
  @run : Run?

  # Creates a new system timer with the specified interval.
  #
  # - `interval` - Time between tick events (default: 16ms for ~60 FPS)
  def initialize(@interval : Time::Span = DEFAULT_INTERVAL)
    @running = Atomic(Bool).new(false)
    @run_token = Atomic(UInt64).new(0_u64)
    @lifecycle_lock = Mutex.new
    @run = nil
  end

  # Returns the current interval between ticks.
  def interval : Time::Span
    @lifecycle_lock.synchronize { @interval }
  end

  # Sets the interval between ticks.
  #
  # Poller instances are not thread-safe, so a running timer applies the change
  # on its owning fiber before this method returns.
  def interval=(value : Time::Span)
    @lifecycle_lock.synchronize do
      previous = @interval
      @interval = value
      begin
        if (run = @run) && owns_run?(run)
          request = IntervalChange.new(value)
          run.interval_changes.send(request)
          signal_run(run)

          select
          when error = request.result.receive
            raise error if error
          when run.done.receive?
            raise run.error || Termisu::Error.new("SystemTimer stopped before changing interval")
          end
        end
      rescue error
        @interval = previous
        raise error
      end
    end
    lifecycle_log { Log.debug { "SystemTimer interval changed to #{value}" } }
  end

  # Starts generating tick events to the output channel.
  #
  # The owning fiber creates and manages the Poller. Startup remains synchronous
  # so acquisition failures are still reported to the caller.
  def start(output : Channel(Event::Any)) : Nil
    @lifecycle_lock.synchronize do
      return if @running.get
      reap_finished_run

      run = Run.new(advance_run_token, output, @interval, monotonic_now)
      @run = run
      @running.set(true)

      spawn(name: "termisu-system-timer") do
        run_loop(run)
      end

      if error = run.started.receive
        run.done.receive?
        @run = nil if @run.same?(run)
        advance_run_token if @run_token.get == run.token
        raise error
      end

      lifecycle_log do
        if poller = run.poller
          Log.debug { "SystemTimer started with interval=#{@interval} using #{poller.class.name}" }
        end
      end
    end
  rescue error
    @running.set(false)
    raise error
  end

  # Stops generating tick events and releases resources.
  #
  # Stop only invalidates and wakes the run. The owning fiber closes its Poller
  # before this method returns, preventing a stale run from touching descriptors
  # acquired by a restart.
  def stop : Nil
    @lifecycle_lock.synchronize do
      run = @run
      return unless run

      if @run_token.get == run.token
        @running.set(false)
        advance_run_token
        signal_run(run)
      end

      run.done.receive?
      @run = nil if @run.same?(run)
      if error = run.error
        raise error
      end

      lifecycle_log { Log.debug { "SystemTimer stopped" } }
    end
  end

  # Returns true if the timer is currently running.
  def running? : Bool
    @running.get
  end

  # Returns the source name for identification.
  def name : String
    "system-timer"
  end

  # Factory seam used by focused lifecycle specs. The public Poller contract is
  # unchanged: SystemTimer alone arranges cooperative waiting around zero-time
  # Poller drains.
  protected def create_poller : Event::Poller
    Event::Poller.create
  end

  # Suspends only this fiber until cancellation or an absolute timer deadline.
  # Absolute deadlines avoid accumulating scheduling and processing overhead.
  protected def wait_for_readiness(
    wakeups : Channel(Nil),
    deadline : MonotonicTime,
  ) : Nil
    remaining = deadline - monotonic_now
    return unless remaining > 0.nanoseconds

    # Sub-millisecond event-loop timeouts are rounded inconsistently across
    # supported Crystal/platform combinations. Rounding only the final wait up
    # cannot accumulate drift because every deadline remains absolute.
    delay = remaining < 1.millisecond ? 1.millisecond : remaining
    select
    when wakeups.receive
    when timeout(delay)
    end
  end

  # Kqueue timers use integer milliseconds. Match that native granularity so the
  # private readiness deadline follows the kernel timer's actual cadence.
  protected def cooperative_interval(interval : Time::Span) : Time::Span
    {% if flag?(:darwin) || flag?(:freebsd) || flag?(:openbsd) %}
      milliseconds = interval.total_milliseconds.to_i64
      Math.max(milliseconds, 1_i64).milliseconds
    {% else %}
      interval
    {% end %}
  end

  private def run_loop(run : Run) : Nil
    poller = begin
      setup_run(run)
    rescue error
      finish_failed_start(run, error)
      return
    end

    run.started.send(nil)

    begin
      run_events(run, poller)
    rescue Channel::ClosedError
      lifecycle_log { Log.debug { "SystemTimer channel closed, exiting" } }
    rescue error
      run.error ||= error
    ensure
      @running.set(false) if @run_token.get == run.token
      close_run_resources(run)
      reject_pending_interval_change(run)
      run.done.close
    end
  end

  private def setup_run(run : Run) : Event::Poller
    poller = create_poller
    run.poller = poller
    run.wait_interval = cooperative_interval(run.interval)
    run.timer_handle = poller.add_timer(run.wait_interval, repeating: true)
    run.next_deadline = monotonic_now + run.wait_interval
    poller
  end

  private def finish_failed_start(run : Run, error : Exception) : Nil
    run.error = error
    @running.set(false) if @run_token.get == run.token
    close_run_resources(run)
    reject_pending_interval_change(run)
    run.done.close
    run.started.send(error)
  end

  private def run_events(run : Run, poller : Event::Poller) : Nil
    start_time = run.start_time
    current_last_tick = start_time
    frame = 0_u64
    pending_missed = 0_u64
    deadline = run.next_deadline
    return unless deadline

    while owns_run?(run)
      wait_for_readiness(run.wakeups, deadline)
      break unless owns_run?(run)

      if apply_interval_change(run, poller)
        next_deadline = run.next_deadline
        return unless next_deadline
        deadline = next_deadline
        next
      end

      result = poller.wait(0.nanoseconds)
      break unless owns_run?(run)

      unless result && result.type.timer?
        Fiber.yield
        break unless owns_run?(run)
        deadline = monotonic_now + 1.millisecond
        run.next_deadline = deadline
        next
      end

      emitted = emit_tick(
        run,
        start_time,
        current_last_tick,
        frame,
        pending_missed,
        result
      )
      break unless emitted

      current_last_tick, frame, pending_missed = emitted
      deadline += run.wait_interval * expiration_count(result.timer_expirations)
      run.next_deadline = deadline
    end
  end

  private def apply_interval_change(run : Run, poller : Event::Poller) : Bool
    request = select
    when value = run.interval_changes.receive
      value
    else
      return false
    end

    error = begin
      handle = run.timer_handle
      raise Termisu::Error.new("SystemTimer has no timer handle") unless handle
      wait_interval = cooperative_interval(request.interval)
      poller.modify_timer(handle, wait_interval)
      run.interval = request.interval
      run.wait_interval = wait_interval
      run.next_deadline = monotonic_now + wait_interval
      nil
    rescue ex
      ex
    end
    request.result.send(error)
    true
  end

  # Emits one Tick event and returns updated per-run state.
  private def emit_tick(
    run : Run,
    start_time : MonotonicTime,
    current_last_tick : MonotonicTime,
    frame : UInt64,
    pending_missed : UInt64,
    result : Event::Poller::PollResult,
  ) : {MonotonicTime, UInt64, UInt64}?
    now = monotonic_now
    elapsed = now - start_time
    delta = now - current_last_tick
    missed = missed_ticks_for(result.timer_expirations, pending_missed)

    tick = Event::Tick.new(
      elapsed: elapsed,
      delta: delta,
      frame: frame,
      missed_ticks: missed,
    )

    # Keep the original-run check adjacent to emission. A stop or restart that
    # happens during either wait must never deliver through this stale run.
    return unless owns_run?(run)
    delivered = send_nonblocking(run.output, tick)

    if delivered && missed > 0
      lifecycle_log { Log.warn { "SystemTimer missed #{missed} tick(s) at frame #{frame}" } }
    end

    {now, frame &+ 1_u64, next_pending_missed(delivered, missed)}
  end

  # Expirations > 1 means the kernel observed dropped intervals.
  private def missed_ticks_for(timer_expirations : UInt64, pending_missed : UInt64) : UInt64
    base_missed = timer_expirations > 0 ? timer_expirations - 1 : 0_u64
    base_missed + pending_missed
  end

  private def expiration_count(value : UInt64) : Int64
    value.clamp(1_u64, Int64::MAX.to_u64).to_i64
  end

  private def owns_run?(run : Run) : Bool
    @running.get && @run_token.get == run.token
  end

  private def signal_run(run : Run) : Nil
    select
    when run.wakeups.send(nil)
    else
      # A pending wakeup already covers this state change.
    end
  end

  # Called only by the run fiber that created and used the Poller.
  private def close_run_resources(run : Run) : Nil
    first_error = run.error

    if poller = run.poller
      error = begin
        poller.close
        nil
      rescue ex
        ex
      end
      first_error ||= error
    end

    run.error = first_error
  end

  private def reject_pending_interval_change(run : Run) : Nil
    select
    when request = run.interval_changes.receive
      request.result.send(run.error || Termisu::Error.new("SystemTimer run stopped"))
    else
    end
  end

  private def reap_finished_run : Nil
    return unless run = @run

    run.done.receive?
    @run = nil
    if error = run.error
      raise error
    end
  end

  # Advances the run token and returns the new value.
  private def advance_run_token : UInt64
    loop do
      current = @run_token.get
      next_token = current &+ 1_u64
      return next_token if @run_token.compare_and_set(current, next_token)[1]
    end
  end
end
