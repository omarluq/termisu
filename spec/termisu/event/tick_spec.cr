require "../../spec_helper"

describe Termisu::Event::Tick do
  describe ".new" do
    it "creates a tick event with all parameters" do
      elapsed = 1.5.seconds
      delta = 16.milliseconds
      frame = 90_u64

      tick = Termisu::Event::Tick.new(elapsed, delta, frame)

      tick.elapsed.should eq(1.5.seconds)
      tick.delta.should eq(16.milliseconds)
      tick.frame.should eq(90_u64)
    end

    it "creates a tick event with named parameters" do
      tick = Termisu::Event::Tick.new(
        elapsed: 500.milliseconds,
        delta: 16.milliseconds,
        frame: 30_u64,
      )

      tick.elapsed.should eq(500.milliseconds)
      tick.delta.should eq(16.milliseconds)
      tick.frame.should eq(30_u64)
    end

    it "handles zero values" do
      tick = Termisu::Event::Tick.new(
        elapsed: Time::Span.zero,
        delta: Time::Span.zero,
        frame: 0_u64,
      )

      tick.elapsed.should eq(Time::Span.zero)
      tick.delta.should eq(Time::Span.zero)
      tick.frame.should eq(0_u64)
    end

    it "handles large elapsed times" do
      elapsed = 24.hours
      delta = 16.milliseconds
      frame = 5_400_000_u64 # 24 hours at 60 FPS

      tick = Termisu::Event::Tick.new(elapsed, delta, frame)

      tick.elapsed.should eq(24.hours)
      tick.frame.should eq(5_400_000_u64)
    end

    it "handles maximum frame counter" do
      # UInt64 max is 18_446_744_073_709_551_615
      tick = Termisu::Event::Tick.new(
        elapsed: 1.second,
        delta: 16.milliseconds,
        frame: UInt64::MAX,
      )

      tick.frame.should eq(UInt64::MAX)
    end
  end

  describe "struct value semantics" do
    it "copies values when assigned" do
      original = Termisu::Event::Tick.new(
        elapsed: 1.second,
        delta: 16.milliseconds,
        frame: 60_u64,
      )

      copy = original

      # Both should have the same values
      copy.elapsed.should eq(original.elapsed)
      copy.delta.should eq(original.delta)
      copy.frame.should eq(original.frame)
    end
  end

  describe "time span operations" do
    it "allows total_seconds on elapsed" do
      tick = Termisu::Event::Tick.new(
        elapsed: 2.5.seconds,
        delta: 16.milliseconds,
        frame: 150_u64,
      )

      tick.elapsed.total_seconds.should eq(2.5)
    end

    it "allows total_milliseconds on delta" do
      tick = Termisu::Event::Tick.new(
        elapsed: 1.second,
        delta: 16.milliseconds,
        frame: 60_u64,
      )

      tick.delta.total_milliseconds.should eq(16.0)
    end
  end
end
