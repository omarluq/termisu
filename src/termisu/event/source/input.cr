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
  #
  # 4ms is a measured stopgap for the idle busy-poll: it cuts idle
  # select(2) calls from ~978/s to ~244/s at the cost of up to 4ms of
  # added input latency when idle. The proper fix (deferred) is evented
  # IO on the input fd — cooperative IO::FileDescriptor wakeup on data,
  # ~20 wakeups/s with lower latency than any fixed sleep.
  IDLE_SLEEP = 4.milliseconds

  # Maximum events drained per loop iteration.
  #
  # Prevents a continuous input stream from monopolizing the scheduler
  # while still allowing bursty input to be processed quickly.
  MAX_DRAIN_PER_CYCLE = 64

  @reader : Termisu::Reader
  @parser : Termisu::Input::Parser
  @running : Atomic(Bool)
  @lifecycle_lock : Mutex
  @stop_signal : Channel(Nil)?
  @done : Channel(Nil)?
  @fiber : Fiber?
  @pending_event : Event::Any?

  # Creates a new input source.
  #
  # - `reader` - Reader instance for raw input
  # - `parser` - Parser instance for escape sequence parsing
  def initialize(@reader : Termisu::Reader, @parser : Termisu::Input::Parser)
    @running = Atomic(Bool).new(false)
    @lifecycle_lock = Mutex.new
  end

  # Starts polling for input events and sending them to the output channel.
  #
  # Spawns a fiber that drains available input events without blocking
  # and sends them to the channel.
  #
  # Serializes lifecycle changes so a previous polling fiber is fully stopped
  # before another can start.
  def start(output : Channel(Event::Any)) : Nil
    @lifecycle_lock.synchronize do
      return if @running.get

      stop_signal = Channel(Nil).new
      done = Channel(Nil).new
      @stop_signal = stop_signal
      @done = done
      @running.set(true)

      @fiber = spawn(name: "termisu-input") do
        run_loop(output, stop_signal)
      ensure
        @running.set(false)
        done.close
      end

      lifecycle_log { Log.debug { "Input source started" } }
    end
  end

  # Stops polling for input events.
  #
  # Signals the polling fiber and waits for it to finish. When this method
  # returns, the parser no longer touches the reader, so ownership can be
  # handed to a raw-input caller without splitting an input sequence.
  def stop : Nil
    @lifecycle_lock.synchronize do
      fiber = @fiber
      return unless fiber
      return if fiber.dead?

      @running.set(false)
      @stop_signal.try { |signal| signal.close unless signal.closed? }
      @done.try(&.receive?)
      lifecycle_log { Log.debug { "Input source stopped" } }
    end
  end

  # Prepares the stopped source to hand its reader to a raw-input consumer.
  #
  # Callers must stop the source first. A parsed event blocked on backpressure
  # and bytes retained by an in-progress parser probe both remain event-owned;
  # handing the reader to a raw consumer in either state would reorder or split
  # the input stream.
  def prepare_raw_handoff : Bool
    @lifecycle_lock.synchronize do
      !@running.get && @pending_event.nil? && @parser.prepare_raw_handoff
    end
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
  private def run_loop(output : Channel(Event::Any), stop_signal : Channel(Nil)) : Nil
    while @running.get
      emitted = false
      drained = 0

      while @running.get && drained < MAX_DRAIN_PER_CYCLE
        event = @pending_event || @parser.poll_event(0)
        break unless event

        unless send_event(output, stop_signal, event)
          # The parser already consumed this complete event. Keep it for the
          # next run instead of losing it when a full output channel is paused.
          @pending_event = event
          return
        end

        @pending_event = nil
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

  private def send_event(
    output : Channel(Event::Any),
    stop_signal : Channel(Nil),
    event : Event::Any,
  ) : Bool
    select
    when output.send(event)
      true
    when stop_signal.receive?
      false
    end
  end
end
