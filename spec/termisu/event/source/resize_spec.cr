require "../../../spec_helper"

unless ENV.delete("TERMISU_RESIZE_SIGNAL_STOP_CHILD").nil?
  source = Termisu::Event::Source::Resize.new(-> { {80, 24} }, poll_interval: 1.hour)
  child_output = Channel(Termisu::Event::Any).new(1)

  16.times do
    source.start(child_output)
    Process.signal(Signal::WINCH, Process.pid)
    source.stop
  end
  sleep 10.milliseconds
  LibC._exit(0)
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
      Fiber.yield # Let fiber start

      # Close channel while source is running
      channel.close
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

      # Wait for multiple poll cycles with timeout - no event should be emitted
      select
      when event = channel.receive
        fail "Should not have received an event, got: #{event}"
      when timeout(50.milliseconds)
        # Good - no event within expected timeframe
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

  describe "completion-safe lifecycle" do
    it "leaves a synchronous provider failure restartable" do
      calls = 0
      provider = -> do
        calls += 1
        raise "injected initial provider failure" if calls == 1
        {80, 24}
      end
      source = Termisu::Event::Source::Resize.new(provider)
      output = Channel(Termisu::Event::Any).new(1)

      expect_raises(Exception, "injected initial provider failure") { source.start(output) }
      source.running?.should be_false
      source.stop

      source.start(output)
      source.running?.should be_true
      source.stop
      output.close
    end

    it "survives a queued SIGWINCH during immediate stop" do
      executable = Process.executable_path || fail "spec executable path is unavailable"
      process_output = IO::Memory.new
      status = Process.run(
        executable,
        env: {"TERMISU_RESIZE_SIGNAL_STOP_CHILD" => "1"},
        output: process_output,
        error: process_output,
      )

      fail "resize shutdown subprocess failed: #{process_output}" unless status.success?
    end

    it "wakes immediately for real SIGWINCH with a long fallback interval" do
      size = MutableSize.new(80, 24)
      source = Termisu::Event::Source::Resize.new(-> { size.to_tuple }, poll_interval: 5.seconds)
      output = Channel(Termisu::Event::Any).new(1)

      source.start(output)

      3.times do |index|
        size.width = 81 + index
        Process.signal(Signal::WINCH, Process.pid)

        select
        when event = output.receive
          event.as(Termisu::Event::Resize).width.should eq(81 + index)
        when timeout(500.milliseconds)
          fail "SIGWINCH did not wake the resize source"
        end
      end

      source.stop
      output.close
    end

    it "deactivates the captured run callback before stop returns" do
      source = Termisu::Event::Source::Resize.new(-> { {80, 24} }, poll_interval: 1.hour)
      output = Channel(Termisu::Event::Any).new(1)

      source.start(output)
      wake = source.@wake || fail "resize wake was not installed"
      handler = Signal::WINCH.trap_handler? || fail "SIGWINCH handler was not installed"
      source.stop

      handler.call(Signal::WINCH)
      select
      when wake.receive
        fail "stopped run callback enqueued a wake"
      else
      end
      output.close
    end

    it "coalesces a burst into one pending size check" do
      calls = Atomic(Int32).new(0)
      second_call = Channel(Nil).new
      release_second = Channel(Nil).new
      third_call = Channel(Nil).new
      provider = -> do
        call = calls.add(1) + 1
        if call == 2
          second_call.send(nil)
          release_second.receive
        elsif call == 3
          third_call.send(nil)
        end
        {80, 24}
      end
      source = Termisu::Event::Source::Resize.new(provider, poll_interval: 1.hour)
      output = Channel(Termisu::Event::Any).new(1)

      source.start(output)
      wake = source.@wake || fail "resize wake was not installed"
      wake.send(nil)
      second_call.receive

      accepted = 0
      32.times do
        select
        when wake.send(nil)
          accepted += 1
        else
        end
      end
      accepted.should eq(1)

      release_second.send(nil)
      third_call.receive
      source.stop
      calls.get.should eq(3)
      output.close
    end

    it "cancels a send blocked by output backpressure before returning" do
      size = MutableSize.new(80, 24)
      queried = Channel(Nil).new(1)
      calls = 0
      provider = -> do
        calls += 1
        queried.send(nil) if calls == 2
        size.to_tuple
      end
      source = Termisu::Event::Source::Resize.new(provider, poll_interval: 1.hour)
      output = Channel(Termisu::Event::Any).new

      source.start(output)
      size.width = 100
      (source.@wake || fail "resize wake was not installed").send(nil)
      queried.receive
      Fiber.yield

      source.stop
      source.running?.should be_false
      calls.should eq(2)
      select
      when event = output.receive
        fail "received event after stop: #{event}"
      else
      end
      output.close
    end

    it "handles output closure while delivering a changed size" do
      size = MutableSize.new(80, 24)
      queried = Channel(Nil).new(1)
      calls = 0
      provider = -> do
        calls += 1
        queried.send(nil) if calls == 2
        size.to_tuple
      end
      source = Termisu::Event::Source::Resize.new(provider, poll_interval: 1.hour)
      output = Channel(Termisu::Event::Any).new

      source.start(output)
      output.close
      size.width = 100
      (source.@wake || fail "resize wake was not installed").send(nil)
      queried.receive
      Fiber.yield

      source.stop
      source.running?.should be_false
    end

    it "joins a provider race and excludes stale wakes from a rapid restart" do
      calls = Atomic(Int32).new(0)
      second_call = Channel(Nil).new
      release_second = Channel(Nil).new
      fourth_call = Channel(Nil).new
      provider = -> do
        call = calls.add(1) + 1
        if call == 2
          second_call.send(nil)
          release_second.receive
        elsif call == 4
          fourth_call.send(nil)
        end
        {80, 24}
      end
      source = Termisu::Event::Source::Resize.new(provider, poll_interval: 1.hour)
      first_output = Channel(Termisu::Event::Any).new(1)
      second_output = Channel(Termisu::Event::Any).new(1)
      stopped = Channel(Nil).new
      restarted = Channel(Nil).new

      source.start(first_output)
      old_wake = source.@wake || fail "resize wake was not installed"
      Process.signal(Signal::WINCH, Process.pid)
      second_call.receive

      spawn do
        source.stop
        stopped.send(nil)
      end
      Fiber.yield
      select
      when stopped.receive
        fail "stop returned while the provider was still running"
      else
      end

      spawn do
        source.start(second_output)
        restarted.send(nil)
      end
      Fiber.yield
      release_second.send(nil)
      stopped.receive
      restarted.receive
      calls.get.should eq(3)

      old_wake.send(nil)
      Fiber.yield
      calls.get.should eq(3)

      Process.signal(Signal::WINCH, Process.pid)
      fourth_call.receive
      source.stop
      calls.get.should eq(4)
      first_output.close
      second_output.close
    end

    it "reports a provider failure once and leaves the source restartable" do
      calls = Atomic(Int32).new(0)
      failed_call = Channel(Nil).new(1)
      provider = -> do
        call = calls.add(1) + 1
        if call == 2
          failed_call.send(nil)
          raise "injected resize provider failure"
        end
        {80, 24}
      end
      source = Termisu::Event::Source::Resize.new(provider, poll_interval: 1.hour)
      output = Channel(Termisu::Event::Any).new(1)

      source.start(output)
      (source.@wake || fail "resize wake was not installed").send(nil)
      failed_call.receive
      Fiber.yield

      expect_raises(Exception, "injected resize provider failure") { source.stop }
      source.running?.should be_false
      source.stop

      source.start(output)
      calls.get.should eq(3)
      source.stop
      output.close
    end
  end

  describe "non-blocking signal handler (BUG-002 regression)" do
    it "delivers resize events via polling without blocking" do
      size = MutableSize.new(80, 24)
      provider = -> { size.to_tuple }
      source = Termisu::Event::Source::Resize.new(provider, poll_interval: 10.milliseconds)
      channel = Channel(Termisu::Event::Any).new(10)

      source.start(channel)
      source.running?.should be_true

      # Change size - event should be delivered via polling + atomic flag
      size.width = 100
      size.height = 50

      select
      when event = channel.receive
        event.should be_a(Termisu::Event::Resize)
        resize = event.as(Termisu::Event::Resize)
        resize.width.should eq(100)
        resize.height.should eq(50)
      when timeout(200.milliseconds)
        fail "Timeout waiting for resize event"
      end

      source.stop
      channel.close
    end

    it "does not deadlock with minimal channel capacity" do
      size = MutableSize.new(80, 24)
      provider = -> { size.to_tuple }
      source = Termisu::Event::Source::Resize.new(provider, poll_interval: 10.milliseconds)
      # Capacity 1 - source must not deadlock if signal handler tried to send
      channel = Channel(Termisu::Event::Any).new(1)

      source.start(channel)

      # Trigger a resize
      size.width = 100
      size.height = 50

      # Drain the channel within timeout - source should not be stuck
      select
      when event = channel.receive
        event.should be_a(Termisu::Event::Resize)
      when timeout(200.milliseconds)
        fail "Source appears deadlocked - resize event not delivered"
      end

      source.stop
      channel.close
    end

    it "continues delivering events after channel was previously drained" do
      size = MutableSize.new(80, 24)
      provider = -> { size.to_tuple }
      source = Termisu::Event::Source::Resize.new(provider, poll_interval: 10.milliseconds)
      channel = Channel(Termisu::Event::Any).new(1)

      source.start(channel)

      # First resize
      size.width = 100
      size.height = 50

      select
      when event = channel.receive
        event.as(Termisu::Event::Resize).width.should eq(100)
      when timeout(200.milliseconds)
        fail "Timeout on first resize"
      end

      # Second resize - source should still be alive and delivering
      size.width = 120
      size.height = 60

      select
      when event = channel.receive
        event.as(Termisu::Event::Resize).width.should eq(120)
      when timeout(200.milliseconds)
        fail "Timeout on second resize - source may have deadlocked"
      end

      source.stop
      channel.close
    end
  end
end
