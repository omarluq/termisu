require "../../spec_helper"

describe Termisu::Event::Source do
  describe "abstract class contract" do
    it "can be subclassed with all abstract methods implemented" do
      source = MockSource.new("test-source")
      source.should be_a(Termisu::Event::Source)
    end

    it "requires name method to return a String" do
      source = MockSource.new("my-source")
      source.name.should eq("my-source")
    end

    it "requires running? method to return a Bool" do
      source = MockSource.new
      source.running?.should be_false
    end
  end

  describe "#start" do
    it "accepts a channel for event output" do
      source = MockSource.new
      channel = Channel(Termisu::Event::Any).new(10)

      source.start(channel)
      source.running?.should be_true

      source.stop
      channel.close
    end

    it "spawns a fiber that sends events to the channel" do
      tick_event = Termisu::Event::Tick.new(
        elapsed: 100.milliseconds,
        delta: 16.milliseconds,
        frame: 1_u64,
      )
      events = [tick_event] of Termisu::Event::Any
      source = MockSource.new("sender", events)
      channel = Channel(Termisu::Event::Any).new(10)

      source.start(channel)
      Fiber.yield # Allow fiber to run

      received = channel.receive
      received.should be_a(Termisu::Event::Tick)

      source.stop
      channel.close
    end
  end

  describe "#stop" do
    it "sets running state to false" do
      source = MockSource.new
      channel = Channel(Termisu::Event::Any).new(10)

      source.start(channel)
      source.running?.should be_true

      source.stop
      source.running?.should be_false

      channel.close
    end

    it "is idempotent (can be called multiple times safely)" do
      source = MockSource.new
      channel = Channel(Termisu::Event::Any).new(10)

      source.start(channel)
      source.stop
      source.stop # Second call should not raise
      source.running?.should be_false

      channel.close
    end
  end

  describe "#running?" do
    it "returns false before start" do
      source = MockSource.new
      source.running?.should be_false
    end

    it "returns true after start" do
      source = MockSource.new
      channel = Channel(Termisu::Event::Any).new(10)

      source.start(channel)
      source.running?.should be_true

      source.stop
      channel.close
    end

    it "returns false after stop" do
      source = MockSource.new
      channel = Channel(Termisu::Event::Any).new(10)

      source.start(channel)
      source.stop
      source.running?.should be_false

      channel.close
    end
  end

  describe "#name" do
    it "returns the source name for identification" do
      source = MockSource.new("keyboard")
      source.name.should eq("keyboard")
    end

    it "is useful for logging and debugging" do
      source = MockSource.new("timer-60fps")
      source.name.should contain("timer")
    end
  end

  describe "double-start prevention" do
    it "prevents starting an already running source" do
      source = MockSource.new
      channel = Channel(Termisu::Event::Any).new(10)

      source.start(channel)
      source.running?.should be_true

      # Second start should be a no-op (compare_and_set pattern)
      source.start(channel)
      source.running?.should be_true

      source.stop
      channel.close
    end
  end

  describe "Channel::ClosedError handling" do
    it "handles closed channel gracefully" do
      tick = Termisu::Event::Tick.new(0.seconds, 0.seconds, 0_u64)
      events = [tick, tick, tick] of Termisu::Event::Any
      source = MockSource.new("test", events)
      channel = Channel(Termisu::Event::Any).new(1)

      source.start(channel)
      Fiber.yield

      # Close channel while source might still be sending
      channel.close
      source.stop

      # Source should have stopped gracefully without raising
      source.running?.should be_false
    end
  end
end
