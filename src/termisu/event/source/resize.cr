# Terminal resize event source.
#
# Monitors terminal size changes via polling and SIGWINCH signal handling.
# Generates `Event::Resize` events with old and new dimensions for
# efficient partial redraws.
#
# ## Usage
#
# ```
# # Create with a size provider (typically backend.size)
# resize = Termisu::Event::Source::Resize.new(-> { backend.size })
#
# loop = Termisu::Event::Loop.new
# loop.add_source(resize)
# loop.start
#
# while event = loop.output.receive?
#   case event
#   when Termisu::Event::Resize
#     puts "Terminal resized to #{event.width}x#{event.height}"
#     if event.changed?
#       puts "Changed from #{event.old_width}x#{event.old_height}"
#     end
#   end
# end
# ```
#
# ## Detection Strategy
#
# Uses a hybrid approach:
# 1. **SIGWINCH Signal**: Non-blockingly wakes the monitoring fiber for an
#    immediate size check. A capacity-one channel coalesces signal bursts.
# 2. **Polling Fallback**: Periodic size checks (default 100ms) catch
#    resizes that signals might miss.
#
# ## Runtime Configuration
#
# The poll interval can be changed while the source is running via
# `poll_interval=`. Changes take effect on the next poll cycle.
#
# ## Thread Safety
#
# Lifecycle changes are serialized. `stop` cancels waits and blocked output,
# then waits for the current run to finish before allowing a restart.
#
# ## Lifecycle
#
# The source can be restarted after stopping. Every run owns its wake,
# cancellation, completion, and signal-handler state, so stale signals cannot
# affect a replacement run.
class Termisu::Event::Source::Resize < Termisu::Event::Source
  Log = Termisu::Logs::Event

  # Default polling interval for size checks.
  # 100ms provides reasonable responsiveness without excessive CPU usage.
  # SIGWINCH signals trigger immediate checks regardless of this interval.
  DEFAULT_POLL_INTERVAL = 100.milliseconds

  # Type alias for the size provider proc.
  alias SizeProvider = -> {Int32, Int32}

  private class RunState
    @active = Atomic(Bool).new(true)

    def active? : Bool
      @active.get
    end

    def deactivate : Nil
      @active.set(false)
    end
  end

  @running : Atomic(Bool)
  @lifecycle_lock : Mutex
  @poll_interval : Time::Span
  @size_provider : SizeProvider
  @wake : Channel(Nil)?
  @stop_signal : Channel(Nil)?
  @done : Channel(Exception?)?
  @run_state : RunState?

  # Creates a new resize source.
  #
  # - `size_provider` - Proc that returns current terminal size as {width, height}
  # - `poll_interval` - Time between size checks (default: 100ms)
  #
  # Example:
  # ```
  # # Using terminal backend
  # resize = Termisu::Event::Source::Resize.new(-> { backend.size })
  #
  # # Custom poll interval for more responsive detection
  # resize = Termisu::Event::Source::Resize.new(
  #   -> { backend.size },
  #   poll_interval: 50.milliseconds
  # )
  # ```
  def initialize(@size_provider : SizeProvider, @poll_interval : Time::Span = DEFAULT_POLL_INTERVAL)
    @running = Atomic(Bool).new(false)
    @lifecycle_lock = Mutex.new
  end

  # Returns the current polling interval.
  def poll_interval : Time::Span
    @poll_interval
  end

  # Sets the polling interval.
  #
  # The new interval takes effect on the next poll cycle.
  # Can be changed while the source is running.
  def poll_interval=(value : Time::Span)
    @poll_interval = value
    Log.debug { "Resize poll interval changed to #{value}" }
  end

  # Starts monitoring for resize events.
  #
  # Installs a SIGWINCH signal handler and spawns a fiber that polls for size
  # changes. Starting an already-running source is an idempotent no-op.
  def start(output : Channel(Event::Any)) : Nil
    @lifecycle_lock.synchronize do
      return if @running.get

      initial_width, initial_height = @size_provider.call
      wake = Channel(Nil).new(1)
      stop_signal = Channel(Nil).new
      done = Channel(Exception?).new(1)
      run_state = RunState.new

      begin
        install_signal_handler(wake, run_state)

        @wake = wake
        @stop_signal = stop_signal
        @done = done
        @run_state = run_state
        @running.set(true)

        spawn(name: "termisu-resize") do
          run(output, wake, stop_signal, done, run_state, initial_width, initial_height)
        end
      rescue error
        run_state.deactivate
        @running.set(false)
        clear_run
        install_inactive_signal_handler rescue nil
        raise error
      end

      lifecycle_log { Log.debug { "Resize source started, initial size: #{initial_width}x#{initial_height}" } }
    end
  end

  # Stops monitoring for resize events.
  #
  # Disables the run-local signal callback, cancels any wait or blocked output
  # send, and waits for the monitoring fiber to acknowledge completion. Once
  # this method returns, the old run cannot query the provider or emit events.
  def stop : Nil
    @lifecycle_lock.synchronize do
      return unless @running.get

      @running.set(false)
      @run_state.try(&.deactivate)

      # Crystal defers signal dispatch through an internal pipe. Replace the
      # run callback with a valid no-op instead of resetting it: an already
      # queued SIGWINCH would otherwise have no handler and terminate Crystal.
      handler_error = begin
        install_inactive_signal_handler
        nil
      rescue error
        error
      end

      @stop_signal.try { |signal| signal.close unless signal.closed? }
      run_error = @done.try(&.receive)
      clear_run

      lifecycle_log { Log.debug { "Resize source stopped" } }
      raise error if error = run_error || handler_error
    end
  end

  # Returns true if the resize source is currently running.
  def running? : Bool
    @running.get
  end

  # Returns the source name for identification.
  def name : String
    "resize"
  end

  # Installs a run-local SIGWINCH handler. The callback never blocks and
  # deliberately swallows all failures because exceptions must not escape a
  # signal trap. A full wake channel means a check is already pending.
  private def install_signal_handler(wake : Channel(Nil), run_state : RunState) : Nil
    Signal::WINCH.trap do
      if run_state.active?
        select
        when wake.send(nil)
        else
        end
      end
    rescue
      # Signal traps are best-effort and must never throw.
    end
  end

  # Crystal may dispatch an already-received signal after stop. This callback
  # keeps that dispatch harmless without retaining any run-local resources.
  private def install_inactive_signal_handler : Nil
    Signal::WINCH.trap do

    rescue
      # Signal traps are best-effort and must never throw.
    end
  end

  private def run(
    output : Channel(Event::Any),
    wake : Channel(Nil),
    stop_signal : Channel(Nil),
    done : Channel(Exception?),
    run_state : RunState,
    initial_width : Int32,
    initial_height : Int32,
  ) : Nil
    error = begin
      run_loop(output, wake, stop_signal, run_state, initial_width, initial_height)
      nil
    rescue Channel::ClosedError
      lifecycle_log { Log.debug { "Resize channel closed, exiting" } }
      nil
    rescue ex
      ex
    end

    # Capacity one makes this final acknowledgement nonblocking. No source
    # state is accessed after it, so receiving it establishes run completion.
    done.send(error)
  end

  # Waits for either a coalesced signal wake or the polling fallback. The stop
  # channel participates in every potentially blocking operation.
  private def run_loop(
    output : Channel(Event::Any),
    wake : Channel(Nil),
    stop_signal : Channel(Nil),
    run_state : RunState,
    initial_width : Int32,
    initial_height : Int32,
  ) : Nil
    last_width = initial_width
    last_height = initial_height

    while run_state.active?
      select
      when wake.receive
      when timeout(@poll_interval)
      when stop_signal.receive?
        return
      end

      return unless run_state.active?

      new_width, new_height = @size_provider.call
      return unless run_state.active?
      next if last_width == new_width && last_height == new_height

      resize_event = Event::Resize.new(
        width: new_width,
        height: new_height,
        old_width: last_width,
        old_height: last_height,
      )

      delivered = select
      when output.send(resize_event)
        true
      when stop_signal.receive?
        false
      end
      return unless delivered

      last_width = new_width
      last_height = new_height
      lifecycle_log do
        Log.debug { "Resize detected: #{resize_event.old_width}x#{resize_event.old_height} -> #{new_width}x#{new_height}" }
      end
    end
  end

  private def clear_run : Nil
    @wake = nil
    @stop_signal = nil
    @done = nil
    @run_state = nil
  end
end
