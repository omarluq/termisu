# Mock Event::Source implementations for testing.
#
# Provides controllable event sources for testing Event::Loop
# and other components that consume events.

# Mock Event::Source for testing.
#
# Allows controlled event emission for predictable tests.
# Supports optional delay between events for timing tests.
#
# Example:
# ```
# events = [Termisu::Event::Key.new(Termisu::Input::Key::LowerA)]
# source = MockSource.new("test", events: events)
#
# channel = Channel(Termisu::Event::Any).new(10)
# source.start(channel)
# event = channel.receive # => Key event
# source.stop
# ```
class MockSource < Termisu::Event::Source
  @running = Atomic(Bool).new(false)
  @output : Channel(Termisu::Event::Any)?
  @fiber : Fiber?
  @events : Array(Termisu::Event::Any)
  @delay : Time::Span

  def initialize(
    @source_name : String = "mock",
    events : Array(Termisu::Event::Any)? = nil,
    @delay : Time::Span = 0.seconds,
  )
    @events = events || [] of Termisu::Event::Any
  end

  def start(output : Channel(Termisu::Event::Any)) : Nil
    return unless @running.compare_and_set(false, true)
    @output = output
    @fiber = spawn(name: "mock-#{@source_name}") do
      @events.each do |event|
        break unless @running.get
        sleep @delay if @delay > 0.seconds
        output.send(event) rescue break
      end
    end
  end

  def stop : Nil
    return unless @running.compare_and_set(true, false)
  end

  def running? : Bool
    @running.get
  end

  def name : String
    @source_name
  end
end

# Slow event source for shutdown timeout testing.
#
# Runs a fiber that sleeps in a loop, useful for testing
# graceful shutdown behavior when sources are slow to stop.
#
# Example:
# ```
# source = SlowSource.new("slow")
# source.start(channel)
# # source.running? => true
# source.stop
# # Fiber will exit on next iteration
# ```
class SlowSource < Termisu::Event::Source
  @running = Atomic(Bool).new(false)
  @fiber : Fiber?

  def initialize(@source_name : String = "slow")
  end

  def start(output : Channel(Termisu::Event::Any)) : Nil
    return unless @running.compare_and_set(false, true)
    @fiber = spawn(name: "slow-source") do
      while @running.get
        sleep 10.milliseconds
      end
    end
  end

  def stop : Nil
    return unless @running.compare_and_set(true, false)
  end

  def running? : Bool
    @running.get
  end

  def name : String
    @source_name
  end
end
