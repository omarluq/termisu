require "../../../spec_helper"

# Helper class to hold mutable size values for testing.
# Crystal closures capture variables by reference, so modifying
# these values will affect the size provider proc.
private class MutableSize
  property width : Int32
  property height : Int32

  def initialize(@width : Int32, @height : Int32)
  end

  def to_tuple : {Int32, Int32}
    {@width, @height}
  end
end

describe Termisu::Event::Source::Resize do
  describe "#initialize" do
    it "creates with a size provider" do
      provider = -> { {80, 24} }
      source = Termisu::Event::Source::Resize.new(provider)
      source.should be_a(Termisu::Event::Source)
      source.running?.should be_false
    end
  end

  describe "#name" do
    it "returns 'resize'" do
      provider = -> { {80, 24} }
      source = Termisu::Event::Source::Resize.new(provider)
      source.name.should eq("resize")
    end
  end

  describe "#poll_interval" do
    it "uses default poll interval of 100ms" do
      provider = -> { {80, 24} }
      source = Termisu::Event::Source::Resize.new(provider)
      source.poll_interval.should eq(100.milliseconds)
    end

    it "accepts custom poll interval" do
      provider = -> { {80, 24} }
      source = Termisu::Event::Source::Resize.new(provider, poll_interval: 50.milliseconds)
      source.poll_interval.should eq(50.milliseconds)
    end

    it "allows runtime poll interval changes" do
      provider = -> { {80, 24} }
      source = Termisu::Event::Source::Resize.new(provider)
      source.poll_interval.should eq(100.milliseconds)

      source.poll_interval = 25.milliseconds
      source.poll_interval.should eq(25.milliseconds)
    end
  end

  describe "#start" do
    it "sets running to true" do
      provider = -> { {80, 24} }
      source = Termisu::Event::Source::Resize.new(provider)
      channel = Channel(Termisu::Event::Any).new(10)

      source.start(channel)
      source.running?.should be_true

      source.stop
      channel.close
    end

    it "prevents double-start (idempotent)" do
      provider = -> { {80, 24} }
      source = Termisu::Event::Source::Resize.new(provider)
      channel = Channel(Termisu::Event::Any).new(10)

      source.start(channel)
      source.start(channel)
      source.running?.should be_true

      source.stop
      channel.close
    end
  end

  describe "#stop" do
    it "sets running to false" do
      provider = -> { {80, 24} }
      source = Termisu::Event::Source::Resize.new(provider)
      channel = Channel(Termisu::Event::Any).new(10)

      source.start(channel)
      source.stop
      source.running?.should be_false

      channel.close
    end

    it "is idempotent (can be called multiple times)" do
      provider = -> { {80, 24} }
      source = Termisu::Event::Source::Resize.new(provider)
      channel = Channel(Termisu::Event::Any).new(10)

      source.start(channel)
      source.stop
      source.stop
      source.running?.should be_false

      channel.close
    end

    it "can be called when not started" do
      provider = -> { {80, 24} }
      source = Termisu::Event::Source::Resize.new(provider)

      # Should not raise
      source.stop
      source.running?.should be_false
    end
  end

  describe "restart lifecycle" do
    it "can be started again after stopping" do
      size = MutableSize.new(80, 24)
      provider = -> { size.to_tuple }
      source = Termisu::Event::Source::Resize.new(provider, poll_interval: 10.milliseconds)
      channel = Channel(Termisu::Event::Any).new(10)

      # First start/stop cycle
      source.start(channel)
      source.running?.should be_true
      source.stop
      source.running?.should be_false

      # Second start should work with new channel
      channel2 = Channel(Termisu::Event::Any).new(10)
      source.start(channel2)
      source.running?.should be_true

      # Verify it still detects resize after restart
      size.width = 120
      size.height = 40

      select
      when event = channel2.receive
        event.should be_a(Termisu::Event::Resize)
        resize = event.as(Termisu::Event::Resize)
        resize.width.should eq(120)
        resize.height.should eq(40)
      when timeout(200.milliseconds)
        fail "Timeout waiting for resize event after restart"
      end

      source.stop
      channel.close
      channel2.close
    end
  end

  describe "Channel::ClosedError handling" do
    it "handles closed channel gracefully during operation" do
      provider = -> { {80, 24} }
      source = Termisu::Event::Source::Resize.new(provider, poll_interval: 10.milliseconds)
      channel = Channel(Termisu::Event::Any).new(1)

      source.start(channel)
      source.running?.should be_true

      # Close channel while source is running
      sleep 20.milliseconds
      channel.close

      # Give fiber time to handle the closed channel
      sleep 20.milliseconds
      source.stop

      # Should have stopped without raising
      source.running?.should be_false
    end
  end

  describe "#running?" do
    it "returns false before start" do
      provider = -> { {80, 24} }
      source = Termisu::Event::Source::Resize.new(provider)
      source.running?.should be_false
    end

    it "returns true after start" do
      provider = -> { {80, 24} }
      source = Termisu::Event::Source::Resize.new(provider)
      channel = Channel(Termisu::Event::Any).new(10)

      source.start(channel)
      source.running?.should be_true

      source.stop
      channel.close
    end

    it "returns false after stop" do
      provider = -> { {80, 24} }
      source = Termisu::Event::Source::Resize.new(provider)
      channel = Channel(Termisu::Event::Any).new(10)

      source.start(channel)
      source.stop
      source.running?.should be_false

      channel.close
    end
  end

  describe "resize detection" do
    it "emits resize event when size changes" do
      # Using MutableSize helper for clearer intent - Crystal closures
      # capture variables by reference, so modifying size affects the provider
      size = MutableSize.new(80, 24)
      provider = -> { size.to_tuple }
      source = Termisu::Event::Source::Resize.new(provider, poll_interval: 10.milliseconds)
      channel = Channel(Termisu::Event::Any).new(10)

      source.start(channel)

      # Change the size (simulate resize)
      size.width = 100
      size.height = 50

      # Wait for event with timeout
      select
      when event = channel.receive
        event.should be_a(Termisu::Event::Resize)
        resize = event.as(Termisu::Event::Resize)
        resize.width.should eq(100)
        resize.height.should eq(50)
        resize.old_width.should eq(80)
        resize.old_height.should eq(24)
      when timeout(200.milliseconds)
        fail "Timeout waiting for resize event"
      end

      source.stop
      channel.close
    end

    it "does not emit when size unchanged" do
      provider = -> { {80, 24} }
      source = Termisu::Event::Source::Resize.new(provider, poll_interval: 10.milliseconds)
      channel = Channel(Termisu::Event::Any).new(10)

      source.start(channel)

      # Wait a bit - no event should be emitted
      sleep 50.milliseconds

      # Channel should be empty (non-blocking check)
      select
      when event = channel.receive
        fail "Should not have received an event, got: #{event}"
      else
        # Good - no event
      end

      source.stop
      channel.close
    end

    it "emits multiple resize events in sequence" do
      size = MutableSize.new(80, 24)
      provider = -> { size.to_tuple }
      source = Termisu::Event::Source::Resize.new(provider, poll_interval: 10.milliseconds)
      channel = Channel(Termisu::Event::Any).new(10)

      source.start(channel)

      # First resize
      size.width = 100
      size.height = 50

      select
      when event = channel.receive
        resize = event.as(Termisu::Event::Resize)
        resize.width.should eq(100)
        resize.height.should eq(50)
        resize.old_width.should eq(80)
        resize.old_height.should eq(24)
      when timeout(200.milliseconds)
        fail "Timeout waiting for first resize event"
      end

      # Second resize - old dimensions should track the previous new values
      size.width = 120
      size.height = 60

      select
      when event = channel.receive
        resize = event.as(Termisu::Event::Resize)
        resize.width.should eq(120)
        resize.height.should eq(60)
        resize.old_width.should eq(100)
        resize.old_height.should eq(50)
      when timeout(200.milliseconds)
        fail "Timeout waiting for second resize event"
      end

      source.stop
      channel.close
    end

    it "tracks old dimensions correctly with changed? helper" do
      size = MutableSize.new(80, 24)
      provider = -> { size.to_tuple }
      source = Termisu::Event::Source::Resize.new(provider, poll_interval: 10.milliseconds)
      channel = Channel(Termisu::Event::Any).new(10)

      source.start(channel)

      size.width = 100
      size.height = 50

      select
      when event = channel.receive
        resize = event.as(Termisu::Event::Resize)
        resize.changed?.should be_true
      when timeout(200.milliseconds)
        fail "Timeout waiting for resize event"
      end

      source.stop
      channel.close
    end
  end
end
