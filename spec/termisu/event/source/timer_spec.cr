require "../../../spec_helper"

describe Termisu::Event::Source::Timer do
  describe "#initialize" do
    it "creates with default interval (16ms)" do
      timer = Termisu::Event::Source::Timer.new
      timer.interval.should eq(16.milliseconds)
    end

    it "creates with custom interval" do
      timer = Termisu::Event::Source::Timer.new(interval: 50.milliseconds)
      timer.interval.should eq(50.milliseconds)
    end

    it "is not running initially" do
      timer = Termisu::Event::Source::Timer.new
      timer.running?.should be_false
    end
  end

  describe "#name" do
    it "returns 'timer'" do
      timer = Termisu::Event::Source::Timer.new
      timer.name.should eq("timer")
    end
  end

  describe "#start" do
    it "sets running to true" do
      timer = Termisu::Event::Source::Timer.new
      channel = Channel(Termisu::Event::Any).new(10)

      timer.start(channel)
      timer.running?.should be_true

      timer.stop
      channel.close
    end

    it "prevents double-start (idempotent)" do
      timer = Termisu::Event::Source::Timer.new
      channel = Channel(Termisu::Event::Any).new(10)

      timer.start(channel)
      timer.running?.should be_true

      # Second start should be a no-op
      timer.start(channel)
      timer.running?.should be_true

      timer.stop
      channel.close
    end
  end

  describe "#stop" do
    it "sets running to false" do
      timer = Termisu::Event::Source::Timer.new
      channel = Channel(Termisu::Event::Any).new(10)

      timer.start(channel)
      timer.running?.should be_true

      timer.stop
      timer.running?.should be_false

      channel.close
    end

    it "is idempotent (can be called multiple times)" do
      timer = Termisu::Event::Source::Timer.new
      channel = Channel(Termisu::Event::Any).new(10)

      timer.start(channel)
      timer.stop
      timer.stop # Second stop should not raise
      timer.running?.should be_false

      channel.close
    end

    it "can be called when not started" do
      timer = Termisu::Event::Source::Timer.new
      # Should not raise
      timer.stop
      timer.running?.should be_false
    end
  end

  describe "#running?" do
    it "returns false before start" do
      timer = Termisu::Event::Source::Timer.new
      timer.running?.should be_false
    end

    it "returns true after start" do
      timer = Termisu::Event::Source::Timer.new
      channel = Channel(Termisu::Event::Any).new(10)

      timer.start(channel)
      timer.running?.should be_true

      timer.stop
      channel.close
    end

    it "returns false after stop" do
      timer = Termisu::Event::Source::Timer.new
      channel = Channel(Termisu::Event::Any).new(10)

      timer.start(channel)
      timer.stop
      timer.running?.should be_false

      channel.close
    end
  end

  describe "#interval" do
    it "returns current interval" do
      timer = Termisu::Event::Source::Timer.new(interval: 33.milliseconds)
      timer.interval.should eq(33.milliseconds)
    end
  end

  describe "#interval=" do
    it "updates interval" do
      timer = Termisu::Event::Source::Timer.new(interval: 16.milliseconds)
      timer.interval = 32.milliseconds
      timer.interval.should eq(32.milliseconds)
    end

    it "can be changed while running" do
      timer = Termisu::Event::Source::Timer.new(interval: 100.milliseconds)
      channel = Channel(Termisu::Event::Any).new(10)

      timer.start(channel)
      timer.interval = 50.milliseconds
      timer.interval.should eq(50.milliseconds)

      timer.stop
      channel.close
    end
  end

  describe "tick events" do
    it "sends Tick events to channel" do
      timer = Termisu::Event::Source::Timer.new(interval: 5.milliseconds)
      channel = Channel(Termisu::Event::Any).new(10)

      timer.start(channel)

      # Wait for at least one tick with timeout
      select
      when event = channel.receive
        event.should be_a(Termisu::Event::Tick)
      when timeout(100.milliseconds)
        fail "Timeout waiting for tick event"
      end

      timer.stop
      channel.close
    end

    it "tick has correct frame counter starting at 0" do
      timer = Termisu::Event::Source::Timer.new(interval: 5.milliseconds)
      channel = Channel(Termisu::Event::Any).new(10)

      timer.start(channel)

      # First tick
      select
      when event = channel.receive
        event.as(Termisu::Event::Tick).frame.should eq(0_u64)
      when timeout(100.milliseconds)
        fail "Timeout waiting for first tick"
      end

      # Second tick
      select
      when event = channel.receive
        event.as(Termisu::Event::Tick).frame.should eq(1_u64)
      when timeout(100.milliseconds)
        fail "Timeout waiting for second tick"
      end

      timer.stop
      channel.close
    end

    it "tick has non-negative elapsed time" do
      timer = Termisu::Event::Source::Timer.new(interval: 5.milliseconds)
      channel = Channel(Termisu::Event::Any).new(10)

      timer.start(channel)

      select
      when event = channel.receive
        tick = event.as(Termisu::Event::Tick)
        tick.elapsed.should be >= 0.nanoseconds
      when timeout(100.milliseconds)
        fail "Timeout waiting for tick"
      end

      timer.stop
      channel.close
    end

    it "tick has non-negative delta time" do
      timer = Termisu::Event::Source::Timer.new(interval: 5.milliseconds)
      channel = Channel(Termisu::Event::Any).new(10)

      timer.start(channel)

      select
      when event = channel.receive
        tick = event.as(Termisu::Event::Tick)
        tick.delta.should be >= 0.nanoseconds
      when timeout(100.milliseconds)
        fail "Timeout waiting for tick"
      end

      timer.stop
      channel.close
    end

    it "elapsed increases over time" do
      timer = Termisu::Event::Source::Timer.new(interval: 5.milliseconds)
      channel = Channel(Termisu::Event::Any).new(10)

      timer.start(channel)

      # Collect two ticks and compare their elapsed times
      ticks = [] of Termisu::Event::Tick
      2.times do
        select
        when event = channel.receive
          ticks << event.as(Termisu::Event::Tick)
        when timeout(100.milliseconds)
          fail "Timeout waiting for tick"
        end
      end

      (ticks[1].elapsed > ticks[0].elapsed).should be_true

      timer.stop
      channel.close
    end
  end

  describe "restart lifecycle" do
    it "can be started again after stopping" do
      timer = Termisu::Event::Source::Timer.new(interval: 5.milliseconds)
      channel = Channel(Termisu::Event::Any).new(10)

      # First start/stop cycle
      timer.start(channel)
      timer.running?.should be_true
      timer.stop
      timer.running?.should be_false

      # Second start should work with new channel
      channel2 = Channel(Termisu::Event::Any).new(10)
      timer.start(channel2)
      timer.running?.should be_true

      # Verify it still generates ticks after restart
      select
      when event = channel2.receive
        event.should be_a(Termisu::Event::Tick)
        # Frame counter should reset to 0 on restart
        event.as(Termisu::Event::Tick).frame.should eq(0_u64)
      when timeout(100.milliseconds)
        fail "Timeout waiting for tick event after restart"
      end

      timer.stop
      channel.close
      channel2.close
    end

    it "resets frame counter on restart" do
      timer = Termisu::Event::Source::Timer.new(interval: 5.milliseconds)
      channel = Channel(Termisu::Event::Any).new(10)

      # First run - get a few ticks
      timer.start(channel)

      last_frame = 0_u64
      3.times do
        select
        when event = channel.receive
          last_frame = event.as(Termisu::Event::Tick).frame
        when timeout(100.milliseconds)
          fail "Timeout waiting for tick"
        end
      end

      # Verify we got past frame 0
      last_frame.should be >= 2_u64

      timer.stop
      timer.running?.should be_false

      # Drain any pending events from the channel to ensure fiber has processed
      loop do
        select
        when channel.receive
          # Discard pending events
        else
          break
        end
      end

      # Wait for the timer fiber to fully exit.
      # The timer fiber checks @running after sleep, so we need to wait
      # at least one interval for it to see the false value and exit.
      # This prevents a race where the old fiber modifies @frame after restart.
      sleep(timer.interval * 2)

      # Restart and verify frame counter reset
      channel2 = Channel(Termisu::Event::Any).new(10)
      timer.start(channel2)

      select
      when event = channel2.receive
        # First tick after restart should be frame 0
        event.as(Termisu::Event::Tick).frame.should eq(0_u64)
      when timeout(100.milliseconds)
        fail "Timeout waiting for tick after restart"
      end

      timer.stop
      channel.close
      channel2.close
    end
  end

  describe "Channel::ClosedError handling" do
    it "handles closed channel gracefully" do
      timer = Termisu::Event::Source::Timer.new(interval: 5.milliseconds)
      channel = Channel(Termisu::Event::Any).new(1)

      timer.start(channel)
      Fiber.yield # Let fiber start

      # Close channel while timer is running
      channel.close
      timer.stop

      # Should have stopped without raising
      timer.running?.should be_false
    end
  end

  describe "thread safety" do
    it "uses Atomic for running state" do
      timer = Termisu::Event::Source::Timer.new
      channel = Channel(Termisu::Event::Any).new(10)
      started = Channel(Nil).new
      stopped = Channel(Nil).new

      # Start and stop from different contexts should be safe
      spawn do
        timer.start(channel)
        started.send(nil)
        stopped.receive # Wait for signal to stop
        timer.stop
      end

      # Wait for start confirmation
      started.receive
      timer.running?.should be_true

      # Signal stop and verify
      stopped.send(nil)
      Fiber.yield
      sleep 5.milliseconds # Brief yield for stop to complete
      timer.running?.should be_false

      channel.close
    end
  end
end
