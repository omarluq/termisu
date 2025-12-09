# Terminal input event source.
#
# Wraps `Reader` and `Input::Parser` to produce Key and Mouse events
# via a dedicated polling fiber. Provides both async (channel-based)
# and sync (legacy) polling modes.
#
# ## Usage
#
# ```
# reader = Termisu::Reader.new(terminal.infd)
# parser = Termisu::Input::Parser.new(reader)
# input = Termisu::Event::Source::Input.new(reader, parser)
#
# loop = Termisu::Event::Loop.new
# loop.add_source(input)
# loop.start
#
# while event = loop.output.receive?
#   case event
#   when Termisu::Event::Key
#     break if event.key.escape?
#   when Termisu::Event::Mouse
#     puts "Click at #{event.x},#{event.y}"
#   end
# end
# ```
#
# ## Legacy Sync Mode
#
# For backward compatibility with sync-based code:
# ```
# if event = input.poll_sync(100)
#   # Handle event directly (bypasses channel)
# end
# ```
#
# ## Thread Safety
#
# Uses `Atomic(Bool)` for the running state. Safe to call `start`/`stop`
# from different fibers.
class Termisu::Event::Source::Input < Termisu::Event::Source
  Log = Termisu::Logs::Event

  # Polling interval for input checking.
  # 10ms provides responsive input without excessive CPU usage.
  POLL_INTERVAL_MS = 10

  @reader : Termisu::Reader
  @parser : Termisu::Input::Parser
  @running : Atomic(Bool)
  @output : Channel(Event::Any)?
  @fiber : Fiber?

  # Creates a new input source.
  #
  # - `reader` - Reader instance for raw input
  # - `parser` - Parser instance for escape sequence parsing
  def initialize(@reader : Termisu::Reader, @parser : Termisu::Input::Parser)
    @running = Atomic(Bool).new(false)
  end

  # Starts polling for input events and sending them to the output channel.
  #
  # Spawns a fiber that polls for input at `POLL_INTERVAL_MS` intervals
  # and sends parsed events to the channel.
  #
  # Prevents double-start with `compare_and_set`.
  def start(output : Channel(Event::Any)) : Nil
    return unless @running.compare_and_set(false, true)

    @output = output

    @fiber = spawn(name: "termisu-input") do
      run_loop
    end

    Log.debug { "Input source started" }
  end

  # Stops polling for input events.
  #
  # Sets the running flag to false, causing the fiber to exit
  # on its next iteration. Uses compare_and_set for idempotent
  # stop operations.
  def stop : Nil
    return unless @running.compare_and_set(true, false)
    Log.debug { "Input source stopped" }
  end

  # Returns true if the input source is currently running.
  def running? : Bool
    @running.get
  end

  # Returns the source name for identification.
  def name : String
    "input"
  end

  # Polls for an input event synchronously (bypasses channel).
  #
  # This provides backward compatibility with sync-based code that
  # doesn't use the async event loop.
  #
  # - `timeout_ms` - Timeout in milliseconds
  #
  # Returns the event or nil if timeout/no data.
  def poll_sync(timeout_ms : Int32) : Event::Any?
    @parser.poll_event(timeout_ms)
  end

  # Main input loop - runs in a spawned fiber.
  private def run_loop : Nil
    output = @output
    return unless output

    while @running.get
      if event = @parser.poll_event(POLL_INTERVAL_MS)
        output.send(event)
      end

      Fiber.yield
    end
  rescue Channel::ClosedError
    # Channel closed during shutdown - exit gracefully
    Log.debug { "Input channel closed, exiting" }
  end
end
