require "../../spec_helper"
require "../../../src/termisu/time_compat"

private class FaultInjectingSource < Termisu::Event::Source
  getter calls = [] of String
  @running = Atomic(Bool).new(false)

  def initialize(
    @source_name : String,
    @start_error : String? = nil,
    @stop_error : String? = nil,
    @all_calls : Array(String)? = nil,
  )
  end

  def start(output : Channel(Termisu::Event::Any)) : Nil
    @calls << "start"
    @all_calls.try { |calls| calls << "#{name}:start" }
    @running.set(true)
    @start_error.try { |error| raise error }
  end

  def stop : Nil
    @calls << "stop"
    @all_calls.try { |calls| calls << "#{name}:stop" }
    @running.set(false)
    @stop_error.try { |error| raise error }
  end

  def running? : Bool
    @running.get
  end

  def name : String
    @source_name
  end
end

private class YieldingStartSource < Termisu::Event::Source
  @running = Atomic(Bool).new(false)
  @start_entered = Channel(Nil).new(1)
  @continue_start = Channel(Nil).new(1)

  def start(output : Channel(Termisu::Event::Any)) : Nil
    @running.set(true)
    @start_entered.send(nil)
    @continue_start.receive
  end

  def stop : Nil
    @running.set(false)
  end

  def running? : Bool
    @running.get
  end

  def name : String
    "yielding-start"
  end

  def wait_until_starting : Nil
    @start_entered.receive
  end

  def continue_start : Nil
    @continue_start.send(nil)
  end
end

describe Termisu::Event::Loop do
  describe "#initialize" do
    it "creates with default buffer size" do
      loop = Termisu::Event::Loop.new
      loop.running?.should be_false
      loop.output.should be_a(Channel(Termisu::Event::Any))
    end

    it "creates with custom buffer size" do
      loop = Termisu::Event::Loop.new(buffer_size: 64)
      loop.running?.should be_false
    end
  end

  describe "#add_source" do
    it "adds a source before start" do
      loop = Termisu::Event::Loop.new
      source = MockSource.new("test")

      loop.add_source(source)
      loop.source_names.should contain("test")
    end

    it "returns self for chaining" do
      loop = Termisu::Event::Loop.new
      source = MockSource.new("test")

      result = loop.add_source(source)
      result.should be(loop)
    end

    it "auto-starts source when loop is already running" do
      loop = Termisu::Event::Loop.new
      loop.start

      source = MockSource.new("late-adder")
      source.running?.should be_false

      loop.add_source(source)
      source.running?.should be_true

      loop.stop
    end

    it "does not start source when loop is not running" do
      loop = Termisu::Event::Loop.new
      source = MockSource.new("early-adder")

      loop.add_source(source)
      source.running?.should be_false
    end
  end

  describe "#remove_source" do
    it "removes a source" do
      loop = Termisu::Event::Loop.new
      source = MockSource.new("removable")

      loop.add_source(source)
      loop.source_names.should contain("removable")

      loop.remove_source(source)
      loop.source_names.should_not contain("removable")
    end

    it "returns self for chaining" do
      loop = Termisu::Event::Loop.new
      source = MockSource.new("test")

      loop.add_source(source)
      result = loop.remove_source(source)
      result.should be(loop)
    end

    it "stops source before removing when running" do
      loop = Termisu::Event::Loop.new
      source = MockSource.new("stoppable")

      loop.add_source(source)
      loop.start
      source.running?.should be_true

      loop.remove_source(source)
      source.running?.should be_false

      loop.stop
    end

    it "handles removing non-existent source gracefully" do
      loop = Termisu::Event::Loop.new
      source = MockSource.new("ghost")

      # Should not raise
      loop.remove_source(source)
      loop.source_names.should be_empty
    end
  end

  describe "#start" do
    it "starts all added sources" do
      loop = Termisu::Event::Loop.new
      source1 = MockSource.new("one")
      source2 = MockSource.new("two")

      loop.add_source(source1)
      loop.add_source(source2)

      source1.running?.should be_false
      source2.running?.should be_false

      loop.start

      source1.running?.should be_true
      source2.running?.should be_true

      loop.stop
    end

    it "sets running state to true" do
      loop = Termisu::Event::Loop.new
      loop.running?.should be_false

      loop.start
      loop.running?.should be_true

      loop.stop
    end

    it "returns self for chaining" do
      loop = Termisu::Event::Loop.new
      result = loop.start
      result.should be(loop)
      loop.stop
    end

    it "prevents double-start" do
      loop = Termisu::Event::Loop.new
      source = MockSource.new("once")
      loop.add_source(source)

      loop.start
      loop.running?.should be_true

      # Second start should be no-op
      loop.start
      loop.running?.should be_true

      loop.stop
    end

    it "rolls back every attempted source in reverse order when startup fails" do
      all_calls = [] of String
      first = FaultInjectingSource.new("first", all_calls: all_calls)
      failing = FaultInjectingSource.new(
        "failing",
        start_error: "startup failed",
        stop_error: "rollback failed",
        all_calls: all_calls,
      )
      unattempted = FaultInjectingSource.new("unattempted", all_calls: all_calls)
      loop = Termisu::Event::Loop.new
      loop.add_source(first).add_source(failing).add_source(unattempted)

      error = expect_raises(Exception, "startup failed") { loop.start }

      error.message.should eq("startup failed")
      loop.running?.should be_false
      first.calls.should eq(["start", "stop"])
      failing.calls.should eq(["start", "stop"])
      unattempted.calls.should be_empty
      all_calls.should eq(["first:start", "failing:start", "failing:stop", "first:stop"])
      first.running?.should be_false
      failing.running?.should be_false
      loop.output.closed?.should be_true

      select
      when event = loop.output.receive?
        event.should be_nil
      when timeout(100.milliseconds)
        fail "Timeout waiting for failed loop output to close"
      end
    end

    it "serializes stop with the complete source startup transition" do
      yielding = YieldingStartSource.new
      following = FaultInjectingSource.new("following")
      loop = Termisu::Event::Loop.new
      loop.add_source(yielding).add_source(following)
      start_done = Channel(Nil).new(1)
      stop_started = Channel(Nil).new(1)
      stop_done = Channel(Nil).new(1)

      spawn do
        loop.start
        start_done.send(nil)
      end
      yielding.wait_until_starting

      spawn do
        stop_started.send(nil)
        loop.stop
        stop_done.send(nil)
      end
      stop_started.receive

      stopped_during_start = select
      when stop_done.receive
        true
      when timeout(30.milliseconds)
        false
      end

      yielding.continue_start
      start_done.receive
      stop_done.receive unless stopped_during_start

      stopped_during_start.should be_false
      loop.running?.should be_false
      yielding.running?.should be_false
      following.running?.should be_false
      following.calls.should eq(["start", "stop"])
      loop.output.closed?.should be_true
    end

    it "does not let direct logging failures change source lifecycle" do
      source = FaultInjectingSource.new("logged")
      loop = Termisu::Event::Loop.new
      loop.add_source(source)

      with_raising_lifecycle_logs do
        loop.start
        loop.running?.should be_true
        source.running?.should be_true

        loop.stop
      end

      loop.running?.should be_false
      source.running?.should be_false
      loop.output.closed?.should be_true
      source.calls.should eq(["start", "stop"])

      # Cleanup completed despite the logger, so retries remain no-ops.
      loop.stop
      source.calls.should eq(["start", "stop"])
    end

    it "preserves existing logging when fault injection block raises" do
      backend = ::Log::MemoryBackend.new
      logger = ::Log.for("termisu.spec.lifecycle")
      builder = ::Log.builder
      was_configured = Termisu::Logging.configured?

      begin
        Termisu::Logging.configured = true
        builder.bind("*", ::Log::Severity::Info, backend)

        begin
          expect_raises(Exception, "injected block failure") do
            with_raising_lifecycle_logs { raise "injected block failure" }
          end

          logger.debug { "filtered debug message" }
          logger.info { "logging remains configured" }

          Termisu::Logging.configured?.should be_true
          backend.entries.map(&.severity).should eq([::Log::Severity::Info])
          backend.entries.map(&.message).should eq(["logging remains configured"])
        ensure
          builder.unbind("*", ::Log::Severity::Info, backend)
        end
      ensure
        Termisu::Logging.configured = was_configured
      end
    end
  end

  describe "#stop" do
    it "stops all sources" do
      loop = Termisu::Event::Loop.new
      source1 = MockSource.new("one")
      source2 = MockSource.new("two")

      loop.add_source(source1)
      loop.add_source(source2)
      loop.start

      source1.running?.should be_true
      source2.running?.should be_true

      loop.stop

      source1.running?.should be_false
      source2.running?.should be_false
    end

    it "sets running state to false" do
      loop = Termisu::Event::Loop.new
      loop.start
      loop.running?.should be_true

      loop.stop
      loop.running?.should be_false
    end

    it "returns self for chaining" do
      loop = Termisu::Event::Loop.new
      loop.start
      result = loop.stop
      result.should be(loop)
    end

    it "closes the output channel" do
      loop = Termisu::Event::Loop.new
      loop.start
      loop.output.closed?.should be_false

      loop.stop
      loop.output.closed?.should be_true
    end

    it "is idempotent (safe to call multiple times)" do
      loop = Termisu::Event::Loop.new
      loop.start

      loop.stop
      loop.running?.should be_false

      # Second stop should not raise
      loop.stop
      loop.running?.should be_false
    end

    it "handles shutdown timeout gracefully" do
      loop = Termisu::Event::Loop.new
      slow = SlowSource.new("slow-stopper")
      loop.add_source(slow)
      loop.start

      # Stop should complete within reasonable time even with slow source
      start_time = monotonic_now
      loop.stop
      elapsed = monotonic_now - start_time

      # Should complete within shutdown timeout + buffer
      elapsed.should be < 200.milliseconds
    end

    it "stops every source and closes output while preserving the first failure" do
      first = FaultInjectingSource.new("first", stop_error: "first stop failed")
      second = FaultInjectingSource.new("second", stop_error: "second stop failed")
      loop = Termisu::Event::Loop.new
      loop.add_source(first).add_source(second)
      loop.start

      expect_raises(Exception, "first stop failed") { loop.stop }

      first.calls.should eq(["start", "stop"])
      second.calls.should eq(["start", "stop"])
      loop.running?.should be_false
      loop.output.closed?.should be_true

      # A failed close still completes the lifecycle and remains idempotent.
      loop.stop
      first.calls.should eq(["start", "stop"])
      second.calls.should eq(["start", "stop"])
    end
  end

  describe "#running?" do
    it "returns false initially" do
      loop = Termisu::Event::Loop.new
      loop.running?.should be_false
    end

    it "returns true after start" do
      loop = Termisu::Event::Loop.new
      loop.start
      loop.running?.should be_true
      loop.stop
    end

    it "returns false after stop" do
      loop = Termisu::Event::Loop.new
      loop.start
      loop.stop
      loop.running?.should be_false
    end
  end

  describe "#output" do
    it "returns the event channel" do
      loop = Termisu::Event::Loop.new
      loop.output.should be_a(Channel(Termisu::Event::Any))
    end

    it "receives events from sources" do
      tick = Termisu::Event::Tick.new(0.seconds, 16.milliseconds, 1_u64)
      events = [tick] of Termisu::Event::Any
      source = MockSource.new("emitter", events)

      loop = Termisu::Event::Loop.new
      loop.add_source(source)
      loop.start

      # Wait for event with timeout
      select
      when received = loop.output.receive
        received.should be_a(Termisu::Event::Tick)
      when timeout(100.milliseconds)
        fail "Timeout waiting for event"
      end
      loop.stop
    end

    it "receives events from multiple sources" do
      tick1 = Termisu::Event::Tick.new(0.seconds, 16.milliseconds, 1_u64)
      tick2 = Termisu::Event::Tick.new(16.milliseconds, 16.milliseconds, 2_u64)

      events1 = [tick1] of Termisu::Event::Any
      events2 = [tick2] of Termisu::Event::Any

      source1 = MockSource.new("source1", events1)
      source2 = MockSource.new("source2", events2)

      loop = Termisu::Event::Loop.new
      loop.add_source(source1)
      loop.add_source(source2)
      loop.start

      # Collect events with timeout
      received = [] of Termisu::Event::Any
      2.times do
        select
        when event = loop.output.receive
          received << event
        when timeout(100.milliseconds)
          break
        end
      end

      received.size.should eq(2)
      loop.stop
    end
  end

  describe "#source_names" do
    it "returns empty array when no sources" do
      loop = Termisu::Event::Loop.new
      loop.source_names.should be_empty
    end

    it "returns names of all sources" do
      loop = Termisu::Event::Loop.new
      loop.add_source(MockSource.new("alpha"))
      loop.add_source(MockSource.new("beta"))
      loop.add_source(MockSource.new("gamma"))

      names = loop.source_names
      names.should contain("alpha")
      names.should contain("beta")
      names.should contain("gamma")
      names.size.should eq(3)
    end

    it "updates after add/remove" do
      loop = Termisu::Event::Loop.new
      source = MockSource.new("dynamic")

      loop.add_source(source)
      loop.source_names.should contain("dynamic")

      loop.remove_source(source)
      loop.source_names.should_not contain("dynamic")
    end
  end

  describe "thread safety" do
    it "uses Atomic for running state" do
      loop = Termisu::Event::Loop.new
      started = Channel(Nil).new
      stopped = Channel(Nil).new

      # Start and stop from different contexts should be safe
      spawn do
        loop.start
        started.send(nil)
        stopped.receive # Wait for signal to stop
        loop.stop
      end

      # Wait for start confirmation
      started.receive
      loop.running?.should be_true

      # Signal stop and verify
      stopped.send(nil)
      Fiber.yield
      sleep 5.milliseconds # Brief yield for stop to complete
      loop.running?.should be_false
    end
  end
end
