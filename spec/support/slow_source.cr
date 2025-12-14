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
