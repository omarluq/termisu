require "../../../spec_helper"

# Exposes the private CAS retry loop so specs can pin its contract.
private class SystemTimerTokenProbe < Termisu::Event::Source::SystemTimer
  def advance_token : UInt64
    advance_run_token
  end

  def current_token : UInt64
    @run_token.get
  end

  def effective_interval(interval : Time::Span) : Time::Span
    cooperative_interval(interval)
  end
end

private class SystemTimerFakePoller < Termisu::Event::Poller
  getter add_calls = 0
  getter modify_calls = 0
  getter wait_calls = 0
  getter close_calls = 0
  getter operation_fibers = [] of Fiber
  getter added_intervals = [] of Time::Span
  getter modified_intervals = [] of Time::Span
  property add_error : Exception?
  property modify_error : Exception?
  property wait_error : Exception?
  property close_error : Exception?
  property drain_started : Channel(Nil)?
  property drain_release : Channel(Nil)?

  @results : Array(PollResult)

  def initialize(@results = [] of PollResult)
  end

  def register_fd(fd : Int32, events : FDEvents) : Nil
  end

  def unregister_fd(fd : Int32) : Nil
  end

  def add_timer(interval : Time::Span, repeating : Bool = true) : TimerHandle
    record_operation
    @add_calls += 1
    @added_intervals << interval
    if error = @add_error
      raise error
    end
    TimerHandle.new(0_u64)
  end

  def modify_timer(handle : TimerHandle, interval : Time::Span) : Nil
    record_operation
    @modify_calls += 1
    @modified_intervals << interval
    if error = @modify_error
      raise error
    end
  end

  def remove_timer(handle : TimerHandle) : Nil
  end

  def wait : PollResult?
    wait(0.nanoseconds)
  end

  def wait(timeout : Time::Span) : PollResult?
    record_operation
    @wait_calls += 1
    @drain_started.try(&.send(nil))
    @drain_release.try(&.receive)
    if error = @wait_error
      raise error
    end
    @results.shift?
  end

  def close : Nil
    record_operation
    @close_calls += 1
    if error = @close_error
      raise error
    end
  end

  private def record_operation : Nil
    @operation_fibers << Fiber.current
  end
end

private class SystemTimerHarness < Termisu::Event::Source::SystemTimer
  getter wait_started = Channel(UInt64).new
  getter wait_release = Channel(Nil).new
  getter deadlines = [] of MonotonicTime
  getter create_calls = 0

  @pollers : Array(Termisu::Event::Poller)

  def initialize(@pollers : Array(Termisu::Event::Poller), interval = 16.milliseconds)
    super(interval)
  end

  protected def create_poller : Termisu::Event::Poller
    @create_calls += 1
    @pollers.shift
  end

  protected def wait_for_readiness(
    wakeups : Channel(Nil),
    deadline : MonotonicTime,
  ) : Nil
    @deadlines << deadline
    @wait_started.send(current_token)
    @wait_release.receive
  end

  private def current_token : UInt64
    @run_token.get
  end
end

private class SystemTimerWaitProbe < Termisu::Event::Source::SystemTimer
  getter wait_started = Channel(Nil).new(1)

  protected def wait_for_readiness(
    wakeups : Channel(Nil),
    deadline : MonotonicTime,
  ) : Nil
    select
    when @wait_started.send(nil)
    else
    end
    super
  end
end

private class SystemTimerCooperativeHarness < SystemTimerWaitProbe
  def initialize(@poller : Termisu::Event::Poller, interval = 16.milliseconds)
    super(interval)
  end

  protected def create_poller : Termisu::Event::Poller
    @poller
  end
end

private class SystemTimerPollFallback < Termisu::Event::Source::SystemTimer
  protected def create_poller : Termisu::Event::Poller
    Termisu::Event::Poller::Poll.new
  end
end

private def wait_until_system_timer_stops(timer : Termisu::Event::Source::SystemTimer) : Nil
  1_000.times do
    return unless timer.running?
    Fiber.yield
  end
  fail "system timer did not stop"
end

describe Termisu::Event::Source::SystemTimer do
  describe "#advance_run_token" do
    it "installs and returns each token sequentially" do
      probe = SystemTimerTokenProbe.new
      first = probe.advance_token
      probe.advance_token.should eq(first + 1)
      probe.current_token.should eq(first + 1)
    end

    it "returns only successfully installed tokens under thread contention" do
      # A failed compare_and_set must retry instead of returning a token that
      # was never installed: across N threads x M advances every returned token
      # is unique and the counter lands exactly N*M higher.
      probe = SystemTimerTokenProbe.new
      start = probe.current_token
      thread_count = 8
      per_thread = 1000
      results = Array(Array(UInt64)).new(thread_count) { Array(UInt64).new(per_thread) }

      threads = (0...thread_count).map do |i|
        Thread.new do
          per_thread.times { results[i] << probe.advance_token }
        end
      end
      threads.each(&.join)

      tokens = results.flatten
      tokens.size.should eq(thread_count * per_thread)
      tokens.uniq.size.should eq(thread_count * per_thread)
      probe.current_token.should eq(start + (thread_count * per_thread).to_u64)
    end
  end

  describe "#cooperative_interval" do
    it "matches native backend granularity without producing a zero interval" do
      probe = SystemTimerTokenProbe.new
      effective = probe.effective_interval(0.5.milliseconds)

      {% if flag?(:darwin) || flag?(:freebsd) || flag?(:openbsd) %}
        effective.should eq(1.millisecond)
      {% else %}
        effective.should eq(0.5.milliseconds)
      {% end %}
    end
  end

  describe "#initialize" do
    it "creates with default interval (16ms)" do
      timer = Termisu::Event::Source::SystemTimer.new
      timer.interval.should eq(16.milliseconds)
    end

    it "creates with custom interval" do
      timer = Termisu::Event::Source::SystemTimer.new(interval: 50.milliseconds)
      timer.interval.should eq(50.milliseconds)
    end

    it "is not running initially" do
      timer = Termisu::Event::Source::SystemTimer.new
      timer.running?.should be_false
    end
  end

  describe "#name" do
    it "returns 'system-timer'" do
      timer = Termisu::Event::Source::SystemTimer.new
      timer.name.should eq("system-timer")
    end
  end

  describe "#start" do
    it "sets running to true" do
      timer = Termisu::Event::Source::SystemTimer.new
      channel = Channel(Termisu::Event::Any).new(10)

      timer.start(channel)
      timer.running?.should be_true

      timer.stop
      channel.close
    end

    it "prevents double-start (idempotent)" do
      timer = Termisu::Event::Source::SystemTimer.new
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
      timer = Termisu::Event::Source::SystemTimer.new
      channel = Channel(Termisu::Event::Any).new(10)

      timer.start(channel)
      timer.running?.should be_true

      timer.stop
      timer.running?.should be_false

      channel.close
    end

    it "is idempotent (can be called multiple times)" do
      timer = Termisu::Event::Source::SystemTimer.new
      channel = Channel(Termisu::Event::Any).new(10)

      timer.start(channel)
      timer.stop
      timer.stop # Second stop should not raise
      timer.running?.should be_false

      channel.close
    end

    it "can be called when not started" do
      timer = Termisu::Event::Source::SystemTimer.new
      # Should not raise
      timer.stop
      timer.running?.should be_false
    end
  end

  describe "#running?" do
    it "returns false before start" do
      timer = Termisu::Event::Source::SystemTimer.new
      timer.running?.should be_false
    end

    it "returns true after start" do
      timer = Termisu::Event::Source::SystemTimer.new
      channel = Channel(Termisu::Event::Any).new(10)

      timer.start(channel)
      timer.running?.should be_true

      timer.stop
      channel.close
    end

    it "returns false after stop" do
      timer = Termisu::Event::Source::SystemTimer.new
      channel = Channel(Termisu::Event::Any).new(10)

      timer.start(channel)
      timer.stop
      timer.running?.should be_false

      channel.close
    end
  end

  describe "#interval" do
    it "returns current interval" do
      timer = Termisu::Event::Source::SystemTimer.new(interval: 33.milliseconds)
      timer.interval.should eq(33.milliseconds)
    end
  end

  describe "#interval=" do
    it "updates interval" do
      timer = Termisu::Event::Source::SystemTimer.new(interval: 16.milliseconds)
      timer.interval = 32.milliseconds
      timer.interval.should eq(32.milliseconds)
    end

    it "can be changed while running" do
      timer = Termisu::Event::Source::SystemTimer.new(interval: 100.milliseconds)
      channel = Channel(Termisu::Event::Any).new(10)

      timer.start(channel)
      timer.interval = 50.milliseconds
      timer.interval.should eq(50.milliseconds)

      timer.stop
      channel.close
    end
  end

  describe "cooperative scheduling" do
    it "lets an independent 1ms fiber progress throughout repeating 50ms waits" do
      progress_samples = [] of Int32

      3.times do
        timer = Termisu::Event::Source::SystemTimer.new(interval: 50.milliseconds)
        channel = Channel(Termisu::Event::Any).new(4)
        progress = Atomic(Int32).new(0)
        progressing = Atomic(Bool).new(true)

        timer.start(channel)
        spawn do
          while progressing.get
            sleep 1.millisecond
            progress.add(1)
          end
        end

        2.times do
          select
          when channel.receive
          when timeout(250.milliseconds)
            fail "Timeout waiting for cooperative timer tick"
          end
        end

        progressing.set(false)
        timer.stop
        progress_samples << progress.get
        channel.close
      end

      progress_samples.each(&.should(be >= 5))
    end

    it "cancels a confirmed long wait promptly across repeated runs" do
      stop_samples = [] of Time::Span

      5.times do
        timer = SystemTimerWaitProbe.new(interval: 2.seconds)
        channel = Channel(Termisu::Event::Any).new(1)
        timer.start(channel)
        timer.wait_started.receive

        stop_samples << Time.measure { timer.stop }
        channel.close
      end

      stop_samples.each(&.should(be < 100.milliseconds))
    end

    it "wakes a long wait when the interval changes" do
      timer = SystemTimerWaitProbe.new(interval: 2.seconds)
      channel = Channel(Termisu::Event::Any).new(1)
      timer.start(channel)
      timer.wait_started.receive

      timer.interval = 10.milliseconds
      select
      when channel.receive
      when timeout(100.milliseconds)
        fail "interval change did not wake the timer wait"
      end

      timer.stop
      channel.close
    end

    it "preserves sustained cadence and tick fields at representative intervals" do
      [6.9.milliseconds, 16.milliseconds, 50.milliseconds].each do |interval|
        timer = Termisu::Event::Source::SystemTimer.new(interval: interval)
        channel = Channel(Termisu::Event::Any).new(32)
        ticks = [] of Termisu::Event::Tick
        timer.start(channel)

        20.times do
          select
          when event = channel.receive
            ticks << event.as(Termisu::Event::Tick)
          when timeout(1.5.seconds)
            fail "Timeout at #{interval} after #{ticks.size} ticks"
          end
        end

        timer.stop
        channel.close

        ticks.map(&.frame).should eq((0_u64...20_u64).to_a)
        ticks.each_cons_pair do |previous, current|
          current.elapsed.should be > previous.elapsed
          current.delta.should be > 0.nanoseconds
        end
        ticks.sum(0.nanoseconds, &.delta).should eq(ticks.last.elapsed)

        effective_interval = {% if flag?(:darwin) || flag?(:freebsd) || flag?(:openbsd) %}
                               interval.total_milliseconds.to_i64.milliseconds
                             {% else %}
                               interval
                             {% end %}
        missed = ticks.sum(0_u64, &.missed_ticks)
        missed.should be <= (effective_interval >= 50.milliseconds ? 4_u64 : 100_u64)

        average_emission_period = ticks.last.elapsed / ticks.size
        average_emission_period.should be > effective_interval * 0.7
        average_emission_period.should be < effective_interval * 6.0
      end
    end

    it "handles sustained interval changes with the Poll fallback" do
      timer = SystemTimerPollFallback.new(interval: 2.seconds)
      channel = Channel(Termisu::Event::Any).new(1)
      completed = Channel(Exception?).new(1)
      timer.start(channel)

      spawn do
        5_000.times { timer.interval = 2.seconds }
        completed.send(nil)
      rescue error
        completed.send(error)
      end

      select
      when error = completed.receive
        raise error if error
      when timeout(10.seconds)
        fail "Poll fallback interval changes did not complete"
      end

      timer.stop
      channel.close
    end
  end

  describe "deterministic run ownership" do
    it "checks the original token after cooperative readiness before draining" do
      poller = SystemTimerFakePoller.new([
        Termisu::Event::Poller::PollResult.new(type: :timer, timer_expirations: 1_u64),
      ])
      timer = SystemTimerHarness.new([poller] of Termisu::Event::Poller)
      output = Channel(Termisu::Event::Any).new(1)
      timer.start(output)
      timer.wait_started.receive

      stopped = Channel(Exception?).new(1)
      spawn do
        timer.stop
        stopped.send(nil)
      rescue error
        stopped.send(error)
      end
      wait_until_system_timer_stops(timer)

      timer.wait_release.send(nil)
      stopped.receive.should be_nil
      poller.wait_calls.should eq(0)
      poller.close_calls.should eq(1)
      select
      when event = output.receive
        fail "stale run emitted #{event.inspect}"
      else
      end
      output.close
    end

    it "checks the original token after the nonblocking Poller drain before emission" do
      drain_started = Channel(Nil).new
      drain_release = Channel(Nil).new
      poller = SystemTimerFakePoller.new([
        Termisu::Event::Poller::PollResult.new(type: :timer, timer_expirations: 1_u64),
      ])
      poller.drain_started = drain_started
      poller.drain_release = drain_release
      timer = SystemTimerHarness.new([poller] of Termisu::Event::Poller)
      output = Channel(Termisu::Event::Any).new(1)
      timer.start(output)
      timer.wait_started.receive
      timer.wait_release.send(nil)
      drain_started.receive

      stopped = Channel(Exception?).new(1)
      spawn do
        timer.stop
        stopped.send(nil)
      rescue error
        stopped.send(error)
      end
      wait_until_system_timer_stops(timer)

      drain_release.send(nil)
      stopped.receive.should be_nil
      select
      when event = output.receive
        fail "stale run emitted #{event.inspect}"
      else
      end
      poller.close_calls.should eq(1)
      output.close
    end

    it "finishes old resource cleanup before a restart acquires replacements" do
      first = SystemTimerFakePoller.new
      second = SystemTimerFakePoller.new
      timer = SystemTimerHarness.new([first, second] of Termisu::Event::Poller)
      first_output = Channel(Termisu::Event::Any).new(1)
      second_output = Channel(Termisu::Event::Any).new(1)
      timer.start(first_output)
      first_token = timer.wait_started.receive

      stopped = Channel(Nil).new
      spawn do
        timer.stop
        stopped.send(nil)
      end
      wait_until_system_timer_stops(timer)

      restarted = Channel(Nil).new
      spawn do
        timer.start(second_output)
        restarted.send(nil)
      end
      100.times { Fiber.yield }
      timer.create_calls.should eq(1)
      first.close_calls.should eq(0)
      second.add_calls.should eq(0)

      timer.wait_release.send(nil)
      stopped.receive
      restarted.receive
      second_token = timer.wait_started.receive

      first.close_calls.should eq(1)
      second.add_calls.should eq(1)
      second_token.should_not eq(first_token)

      stopped_again = Channel(Nil).new
      spawn do
        timer.stop
        stopped_again.send(nil)
      end
      wait_until_system_timer_stops(timer)
      timer.wait_release.send(nil)
      stopped_again.receive
      second.close_calls.should eq(1)
      first_output.close
      second_output.close
    end

    it "keeps every Poller operation on the owning run fiber" do
      poller = SystemTimerFakePoller.new
      timer = SystemTimerCooperativeHarness.new(poller)
      output = Channel(Termisu::Event::Any).new(1)
      timer.start(output)
      timer.wait_started.receive

      timer.interval = 30.milliseconds
      timer.stop

      poller.add_calls.should eq(1)
      poller.modify_calls.should eq(1)
      poller.close_calls.should eq(1)
      poller.operation_fibers.uniq.size.should eq(1)
      output.close
    end

    it "keeps fallback readiness on absolute cadence deadlines" do
      poller = SystemTimerFakePoller.new([
        Termisu::Event::Poller::PollResult.new(type: :timer, timer_expirations: 1_u64),
        Termisu::Event::Poller::PollResult.new(type: :timer, timer_expirations: 1_u64),
      ])
      interval = 6.milliseconds
      timer = SystemTimerHarness.new([poller] of Termisu::Event::Poller, interval)
      output = Channel(Termisu::Event::Any).new(2)
      timer.start(output)

      2.times do
        timer.wait_started.receive
        timer.wait_release.send(nil)
        output.receive
      end
      timer.wait_started.receive

      (timer.deadlines[1] - timer.deadlines[0]).should eq(interval)
      (timer.deadlines[2] - timer.deadlines[1]).should eq(interval)

      stopped = Channel(Nil).new
      spawn do
        timer.stop
        stopped.send(nil)
      end
      wait_until_system_timer_stops(timer)
      timer.wait_release.send(nil)
      stopped.receive
      output.close
    end

    it "preserves kernel expirations, frames, and timing fields" do
      poller = SystemTimerFakePoller.new([
        Termisu::Event::Poller::PollResult.new(type: :timer, timer_expirations: 3_u64),
        Termisu::Event::Poller::PollResult.new(type: :timer, timer_expirations: 1_u64),
      ])
      timer = SystemTimerHarness.new([poller] of Termisu::Event::Poller)
      output = Channel(Termisu::Event::Any).new(2)
      timer.start(output)

      timer.wait_started.receive
      timer.wait_release.send(nil)
      first = output.receive.as(Termisu::Event::Tick)
      timer.wait_started.receive
      timer.wait_release.send(nil)
      second = output.receive.as(Termisu::Event::Tick)
      timer.wait_started.receive

      first.frame.should eq(0_u64)
      first.missed_ticks.should eq(2_u64)
      second.frame.should eq(1_u64)
      second.missed_ticks.should eq(0_u64)
      second.elapsed.should be >= first.elapsed
      first.delta.should be >= 0.nanoseconds
      second.delta.should be >= 0.nanoseconds

      stopped = Channel(Nil).new
      spawn do
        timer.stop
        stopped.send(nil)
      end
      wait_until_system_timer_stops(timer)
      timer.wait_release.send(nil)
      stopped.receive
      poller.close_calls.should eq(1)
      output.close
    end
  end

  describe "failure cleanup" do
    it "preserves an add failure when startup cleanup also fails" do
      poller = SystemTimerFakePoller.new
      poller.add_error = Exception.new("add failed")
      poller.close_error = Exception.new("close failed")
      timer = SystemTimerHarness.new([poller] of Termisu::Event::Poller)
      output = Channel(Termisu::Event::Any).new(1)

      expect_raises(Exception, "add failed") { timer.start(output) }
      poller.add_calls.should eq(1)
      poller.close_calls.should eq(1)
      timer.running?.should be_false
      timer.stop
      output.close
    end

    it "reports owner-fiber interval modification failure without stale cleanup" do
      poller = SystemTimerFakePoller.new
      poller.modify_error = Exception.new("modify failed")
      timer = SystemTimerCooperativeHarness.new(poller)
      output = Channel(Termisu::Event::Any).new(1)
      timer.start(output)
      timer.wait_started.receive

      expect_raises(Exception, "modify failed") { timer.interval = 30.milliseconds }
      timer.interval.should eq(16.milliseconds)
      poller.modify_calls.should eq(1)

      timer.stop
      poller.close_calls.should eq(1)
      output.close
    end

    it "keeps a wait failure ahead of a cleanup failure and stays idempotent" do
      poller = SystemTimerFakePoller.new
      poller.wait_error = Exception.new("wait failed")
      poller.close_error = Exception.new("close failed")
      timer = SystemTimerHarness.new([poller] of Termisu::Event::Poller)
      output = Channel(Termisu::Event::Any).new(1)
      timer.start(output)
      timer.wait_started.receive
      timer.wait_release.send(nil)
      wait_until_system_timer_stops(timer)

      expect_raises(Exception, "wait failed") { timer.stop }
      poller.close_calls.should eq(1)
      timer.stop
      poller.close_calls.should eq(1)
      output.close
    end

    it "reports a close failure once" do
      poller = SystemTimerFakePoller.new
      poller.close_error = Exception.new("close failed")
      timer = SystemTimerHarness.new([poller] of Termisu::Event::Poller)
      output = Channel(Termisu::Event::Any).new(1)
      timer.start(output)
      timer.wait_started.receive

      stopped = Channel(Exception?).new(1)
      spawn do
        timer.stop
        stopped.send(nil)
      rescue error
        stopped.send(error)
      end
      wait_until_system_timer_stops(timer)
      timer.wait_release.send(nil)

      stopped.receive.try(&.message).should eq("close failed")
      poller.close_calls.should eq(1)
      timer.stop
      poller.close_calls.should eq(1)
      output.close
    end
  end

  describe "tick events" do
    it "sends Tick events to channel" do
      timer = Termisu::Event::Source::SystemTimer.new(interval: 10.milliseconds)
      channel = Channel(Termisu::Event::Any).new(10)

      timer.start(channel)

      # Wait for at least one tick with timeout
      select
      when event = channel.receive
        event.should be_a(Termisu::Event::Tick)
      when timeout(200.milliseconds)
        fail "Timeout waiting for tick event"
      end

      timer.stop
      channel.close
    end

    it "tick has correct frame counter starting at 0" do
      timer = Termisu::Event::Source::SystemTimer.new(interval: 10.milliseconds)
      channel = Channel(Termisu::Event::Any).new(10)

      timer.start(channel)

      # First tick
      select
      when event = channel.receive
        event.as(Termisu::Event::Tick).frame.should eq(0_u64)
      when timeout(200.milliseconds)
        fail "Timeout waiting for first tick"
      end

      # Second tick
      select
      when event = channel.receive
        event.as(Termisu::Event::Tick).frame.should eq(1_u64)
      when timeout(200.milliseconds)
        fail "Timeout waiting for second tick"
      end

      timer.stop
      channel.close
    end

    it "tick has non-negative elapsed time" do
      timer = Termisu::Event::Source::SystemTimer.new(interval: 10.milliseconds)
      channel = Channel(Termisu::Event::Any).new(10)

      timer.start(channel)

      select
      when event = channel.receive
        tick = event.as(Termisu::Event::Tick)
        tick.elapsed.should be >= 0.nanoseconds
      when timeout(200.milliseconds)
        fail "Timeout waiting for tick"
      end

      timer.stop
      channel.close
    end

    it "tick has non-negative delta time" do
      timer = Termisu::Event::Source::SystemTimer.new(interval: 10.milliseconds)
      channel = Channel(Termisu::Event::Any).new(10)

      timer.start(channel)

      select
      when event = channel.receive
        tick = event.as(Termisu::Event::Tick)
        tick.delta.should be >= 0.nanoseconds
      when timeout(200.milliseconds)
        fail "Timeout waiting for tick"
      end

      timer.stop
      channel.close
    end

    it "tick includes missed_ticks field" do
      timer = Termisu::Event::Source::SystemTimer.new(interval: 10.milliseconds)
      channel = Channel(Termisu::Event::Any).new(10)

      timer.start(channel)

      select
      when event = channel.receive
        tick = event.as(Termisu::Event::Tick)
        # Verify missed_ticks field exists and is valid UInt64
        # (may be >0 on slow CI runners due to scheduler delay)
        tick.missed_ticks.should be_a(UInt64)
      when timeout(200.milliseconds)
        fail "Timeout waiting for tick"
      end

      timer.stop
      channel.close
    end

    it "elapsed increases over time" do
      timer = Termisu::Event::Source::SystemTimer.new(interval: 10.milliseconds)
      channel = Channel(Termisu::Event::Any).new(10)

      timer.start(channel)

      # Collect two ticks and compare their elapsed times
      ticks = [] of Termisu::Event::Tick
      2.times do
        select
        when event = channel.receive
          ticks << event.as(Termisu::Event::Tick)
        when timeout(200.milliseconds)
          fail "Timeout waiting for tick"
        end
      end

      (ticks[1].elapsed > ticks[0].elapsed).should be_true

      timer.stop
      channel.close
    end

    it "reports missed_ticks when output channel is backpressured" do
      timer = Termisu::Event::Source::SystemTimer.new(interval: 2.milliseconds)
      channel = Channel(Termisu::Event::Any).new(1)

      timer.start(channel)

      # Intentionally do not consume to force drops while buffer is full.
      sleep 30.milliseconds

      # First tick may have been queued before backpressure accumulated.
      select
      when channel.receive
      when timeout(100.milliseconds)
        fail "Timeout waiting for first tick"
      end

      # Next delivered tick should carry dropped-frame accounting.
      select
      when event = channel.receive
        tick = event.as(Termisu::Event::Tick)
        tick.missed_ticks.should be >= 1_u64
      when timeout(150.milliseconds)
        fail "Timeout waiting for backpressure tick"
      end

      timer.stop
      channel.close
    end
  end

  describe "restart lifecycle" do
    it "can be started again after stopping" do
      timer = Termisu::Event::Source::SystemTimer.new(interval: 10.milliseconds)
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
      when timeout(200.milliseconds)
        fail "Timeout waiting for tick event after restart"
      end

      timer.stop
      channel.close
      channel2.close
    end

    it "resets frame counter on restart" do
      timer = Termisu::Event::Source::SystemTimer.new(interval: 10.milliseconds)
      channel = Channel(Termisu::Event::Any).new(10)

      # First run - get a few ticks
      timer.start(channel)

      last_frame = 0_u64
      3.times do
        select
        when event = channel.receive
          last_frame = event.as(Termisu::Event::Tick).frame
        when timeout(200.milliseconds)
          fail "Timeout waiting for tick"
        end
      end

      # Verify we got past frame 0
      last_frame.should be >= 2_u64

      timer.stop
      timer.running?.should be_false

      # Drain any pending events from the channel
      loop do
        select
        when channel.receive
          # Discard pending events
        else
          break
        end
      end

      # Wait for timer fiber to fully exit
      sleep(timer.interval * 2)

      # Restart and verify frame counter reset
      channel2 = Channel(Termisu::Event::Any).new(10)
      timer.start(channel2)

      select
      when event = channel2.receive
        # First tick after restart should be frame 0
        event.as(Termisu::Event::Tick).frame.should eq(0_u64)
      when timeout(200.milliseconds)
        fail "Timeout waiting for tick after restart"
      end

      timer.stop
      channel.close
      channel2.close
    end
  end

  describe "Channel::ClosedError handling" do
    it "handles closed channel gracefully" do
      timer = Termisu::Event::Source::SystemTimer.new(interval: 10.milliseconds)
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
      timer = Termisu::Event::Source::SystemTimer.new
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
      sleep 10.milliseconds # Brief yield for stop to complete
      timer.running?.should be_false

      channel.close
    end
  end
end
