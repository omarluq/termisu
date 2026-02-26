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
# 1. **SIGWINCH Signal**: Immediate notification when terminal is resized
# 2. **Polling Fallback**: Periodic checks (default 100ms) as a safety net
#
# The signal handler wakes the polling fiber immediately, providing
# responsive resize detection while the polling serves as a fallback
# for edge cases where signals might be missed.
#
# ## Runtime Configuration
#
# The poll interval can be changed while the source is running via
# `poll_interval=`. Changes take effect on the next poll cycle.
#
# ## Thread Safety
#
# Uses `Atomic(Bool)` for the running state. Safe to call `start`/`stop`
# from different fibers. Uses `compare_and_set` for idempotent lifecycle
# operations - calling `start` twice or `stop` twice is safe.
#
# ## Lifecycle
#
# The source can be restarted after stopping. Each `start` resets the
# signal flag and reinstalls the SIGWINCH handler.
class Termisu::Event::Source::Resize < Termisu::Event::Source
  Log = Termisu::Logs::Event

  # Default polling interval for size checks.
  # 100ms provides reasonable responsiveness without excessive CPU usage.
  # SIGWINCH signals trigger immediate checks regardless of this interval.
  DEFAULT_POLL_INTERVAL = 100.milliseconds

  # Type alias for the size provider proc.
  alias SizeProvider = -> {Int32, Int32}

  @running : Atomic(Bool)
  @signal_received : Atomic(Bool)
  @generation : Atomic(Int32)
  @poll_interval : Time::Span
  @size_provider : SizeProvider
  @output : Channel(Event::Any)?
  @fiber : Fiber?
  @last_width : Int32?
  @last_height : Int32?

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
    @signal_received = Atomic(Bool).new(false)
    @generation = Atomic(Int32).new(0)
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
  # Installs a SIGWINCH signal handler and spawns a fiber that
  # polls for size changes. Events are sent to the output channel.
  #
  # Prevents double-start with `compare_and_set`.
  def start(output : Channel(Event::Any)) : Nil
    return unless @running.compare_and_set(false, true)

    @output = output

    # Reset signal flag for this run
    @signal_received.set(false)

    # Get initial size
    initial_width, initial_height = @size_provider.call
    @last_width = initial_width
    @last_height = initial_height

    # Install SIGWINCH handler
    install_signal_handler

    gen = @generation.add(1) &+ 1
    @fiber = spawn(name: "termisu-resize") do
      run_loop(gen)
    end

    Log.debug { "Resize source started, initial size: #{initial_width}x#{initial_height}" }
  end

  # Stops monitoring for resize events.
  #
  # Sets the running flag to false, causing the fiber to exit
  # on its next poll cycle. Resets the SIGWINCH handler.
  def stop : Nil
    return unless @running.compare_and_set(true, false)

    # Invalidate the current generation so any stale fiber self-terminates
    @generation.add(1)

    # Reset signal handler first to prevent new signals from arriving
    Signal::WINCH.reset

    # Give fiber time to exit gracefully (it will notice @running is false
    # on its next poll cycle, up to one @poll_interval delay)
    Fiber.yield

    Log.debug { "Resize source stopped" }
  end

  # Returns true if the resize source is currently running.
  def running? : Bool
    @running.get
  end

  # Returns the source name for identification.
  def name : String
    "resize"
  end

  # Installs the SIGWINCH signal handler.
  #
  # Uses an `Atomic(Bool)` flag instead of a channel send, because
  # `Channel#send` can block when the buffer is full, which is unsafe
  # inside a signal handler. `Atomic#set` is always non-blocking.
  private def install_signal_handler : Nil
    signal_received = @signal_received
    Signal::WINCH.trap do
      signal_received.set(true)
    end
  end

  # Main resize monitoring loop - runs in a spawned fiber.
  #
  # Polls at `@poll_interval` and checks the `@signal_received` atomic flag.
  # When a SIGWINCH signal is received, the flag is set by the signal handler
  # and the next poll cycle processes the resize. Maximum latency for signal-
  # triggered resizes is one poll interval (100ms by default).
  private def run_loop(my_generation : Int32) : Nil
    output = @output
    return unless output

    while @running.get
      sleep(@poll_interval)

      # Check generation after sleep — if it changed, a stop+start cycle
      # occurred and a new fiber owns this generation. Self-terminate.
      break unless @generation.get == my_generation
      break unless @running.get

      # Clear the signal flag (swap returns previous value).
      # We check size regardless of whether a signal triggered it,
      # since the poll also catches resizes missed by signals.
      @signal_received.swap(false)

      check_and_emit_resize(output)
    end
  end

  # Checks for size changes and emits resize event if changed.
  #
  # Compares current size from the provider against the last known size.
  # If different, creates a `Event::Resize` with both old and new dimensions
  # and sends it to the output channel. Updates last known size for the
  # next comparison.
  #
  # NOTE: If the output channel is closed (e.g., during shutdown), the
  # `output.send` call will raise Channel::ClosedError, which propagates
  # up through run_loop and terminates the fiber.
  private def check_and_emit_resize(output : Channel(Event::Any)) : Nil
    new_width, new_height = @size_provider.call

    old_width = @last_width
    old_height = @last_height

    # Detect if size changed (comparing against last emitted dimensions)
    if old_width != new_width || old_height != new_height
      resize_event = Event::Resize.new(
        width: new_width,
        height: new_height,
        old_width: old_width,
        old_height: old_height,
      )

      # Update last known size BEFORE sending to ensure consistency
      # even if the channel send blocks briefly
      @last_width = new_width
      @last_height = new_height

      output.send(resize_event)
      Log.debug { "Resize detected: #{old_width}x#{old_height} -> #{new_width}x#{new_height}" }
    end
  end
end
