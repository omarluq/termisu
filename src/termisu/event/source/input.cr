# Terminal input event source.
#
# Wraps `Reader` and `Input::Parser` to produce Key and Mouse events
# via a dedicated polling fiber.
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
# ## Thread Safety
#
# Uses `Atomic(Bool)` for the running state. Safe to call `start`/`stop`
# from different fibers.
class Termisu::Event::Source::Input < Termisu::Event::Source
  Log = Termisu::Logs::Event

  # Idle sleep when no input is available.
  #
  # Keeps CPU usage low without introducing long blocking waits that
  # can starve high-frequency timers.
  IDLE_SLEEP = 1.millisecond

  # Maximum events drained per loop iteration.
  #
  # Prevents a continuous input stream from monopolizing the scheduler
  # while still allowing bursty input to be processed quickly.
  MAX_DRAIN_PER_CYCLE = 64

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
  # Spawns a fiber that drains available input events without blocking
  # and sends them to the channel.
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

  # Main input loop - runs in a spawned fiber.
  private def run_loop : Nil
    output = @output
    return unless output

    while @running.get
      emitted = false
      drained = 0

      while @running.get && drained < MAX_DRAIN_PER_CYCLE
        event = @parser.poll_event(0)
        break unless event

        output.send(event)
        emitted = true
        drained += 1
      end

      break unless @running.get

      if emitted
        Fiber.yield
      else
        sleep IDLE_SLEEP
      end
    end
  rescue Channel::ClosedError
    # Channel closed during shutdown - exit gracefully
    Log.debug { "Input channel closed, exiting" }
  end
end
