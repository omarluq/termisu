require "./spec_helper"

# Whether this process has a usable controlling terminal.
#
# `File.exists?("/dev/tty")` is not enough: the node exists in CI containers and
# sandboxes that have no controlling terminal, where opening it fails with ENXIO.
# Opening it is what distinguishes the two, and it is what `Termisu.new` effectively
# does — so this guard runs the spec below on exactly the machines where it is
# meaningful, instead of skipping it wherever the node happens to exist.
private def controlling_tty? : Bool
  File.open("/dev/tty", "w", &.close)
  true
rescue
  false
end

# Test-only input source that records facade pause/resume handoffs without
# starting a reader fiber.
private class PausableInputSource < Termisu::Event::Source::Input
  getter start_count : Int32 = 0
  getter stop_count : Int32 = 0
  @test_running : Bool = false

  def start(_output : Channel(Termisu::Event::Any)) : Nil
    @start_count += 1
    @test_running = true
  end

  def stop : Nil
    @stop_count += 1
    @test_running = false
  end

  def running? : Bool
    @test_running
  end
end

# Forces close to run after the facade has decided to restart input but before
# the source records that restart. The production ownership lock must make the
# close fiber wait until start returns, so Event::Loop#stop wins last.
private class CloseDuringRestartInputSource < PausableInputSource
  @close_during_start : Termisu?
  @close_done = Channel(Exception?).new(1)

  def close_during_next_start(termisu : Termisu) : Nil
    @close_during_start = termisu
  end

  def start(output : Channel(Termisu::Event::Any)) : Nil
    if termisu = @close_during_start
      @close_during_start = nil
      close_started = Channel(Nil).new
      spawn do
        close_started.send(nil)
        error = nil.as(Exception?)
        begin
          termisu.close
        rescue ex
          error = ex
        ensure
          @close_done.send(error)
        end
      end

      # Let close either acquire the ownership lock (the regression) or block
      # behind this in-progress restart (the fixed behavior).
      close_started.receive
      Fiber.yield
    end

    super(output)
  end

  def wait_for_close : Nil
    if error = @close_done.receive
      raise error
    end
  end
end

# Event source whose worker enters a mode scope and whose stop synchronously
# joins that worker. This exercises the close lock order: close must not retain
# the facade mode gate while Event::Loop#stop joins a source queued on it.
private class JoiningModeSource < Termisu::Event::Source
  @running = Atomic(Bool).new(false)
  @termisu : Termisu? = nil
  @trigger = Channel(Nil).new
  @attempting = Channel(Nil).new
  @done = Channel(Nil).new

  def termisu=(termisu : Termisu) : Termisu
    @termisu = termisu
  end

  def start(output : Channel(Termisu::Event::Any)) : Nil
    _ = output
    return unless @running.compare_and_set(false, true)[1]

    spawn do
      @trigger.receive
      @attempting.send(nil)
      if termisu = @termisu
        termisu.with_mode(Termisu::Terminal::Mode.raw) { }
      else
        raise "joining mode source has no Termisu instance"
      end
    rescue Termisu::Error
      # Close began before the queued scope entered, so rejection is expected.
    ensure
      @running.set(false)
      @done.close
    end
  end

  def enter_mode : Nil
    @trigger.send(nil)
    @attempting.receive
  end

  def stop : Nil
    @running.set(false)
    @done.receive?
  end

  def running? : Bool
    @running.get
  end

  def name : String
    "joining-mode"
  end
end

private class FailingStopEventLoop < Termisu::Event::Loop
  getter stop_count : Int32 = 0

  def stop : self
    @stop_count += 1
    raise IO::Error.new("event loop stop failed")
  end
end

private class FailingCloseTerminal < CaptureTerminal
  getter close_count : Int32 = 0

  def close : Nil
    return super if closed?

    @close_count += 1
    super
    raise IO::Error.new("terminal close failed")
  end
end

private class LifecycleTerminal < CaptureTerminal
  class_property? fail_close : Bool = false

  def close
    super
    @backend.close
    raise "terminal cleanup failed" if self.class.fail_close?
  end
end

private class LifecycleEventLoop < Termisu::Event::Loop
  class_property? fail_start : Bool = false
  class_property? fail_stop : Bool = false
  getter stop_calls : Int32 = 0

  def start : self
    super
    raise "source startup failed" if self.class.fail_start?
    self
  end

  def stop : self
    @stop_calls += 1
    super
    raise "event stop failed" if self.class.fail_stop?
    self
  end
end

private class LifecycleTermisu < Termisu
  class_property last_terminal : LifecycleTerminal?
  class_property last_event_loop : LifecycleEventLoop?

  protected def build_terminal(sync_updates : Bool) : Termisu::Terminal
    terminal = LifecycleTerminal.new(sync_updates: sync_updates)
    self.class.last_terminal = terminal
    terminal
  end

  protected def build_event_loop : Termisu::Event::Loop
    event_loop = LifecycleEventLoop.new
    self.class.last_event_loop = event_loop
    event_loop
  end
end

# Build the public facade around controlled collaborators so mode coordination
# can be tested independently of its normal initialization lifecycle.
class Termisu
  def initialize(
    @terminal : Terminal,
    @reader : Reader,
    @input_parser : Input::Parser,
    @input_source : Event::Source::Input,
    @resize_source : Event::Source::Resize,
    @event_loop : Event::Loop,
  )
    @ownership = TerminalOwnership.acquire
    @closed = Atomic(Bool).new(false)
    @timer_source = nil
    @mode_scope_gate = ModeScopeGate.new
    @input_ownership_lock = Mutex.new
    @raw_input_owner = nil
    @raw_input_depth = 0
    @input_pause_depth = 0
  end
end

describe Termisu do
  it "has a version number" do
    Termisu::VERSION.should_not be_nil
  end

  describe ".new" do
    # Successful initialization is exercised in examples/demo.cr: constructing Termisu
    # here would switch to the alternate screen and corrupt spec output. What is worth
    # asserting in-suite is the failure path, and that needs a machine without a
    # controlling terminal — so the guard is applied when the spec is declared rather
    # than swallowed at runtime.
    if controlling_tty?
      pending "raises IO::Error without a controlling TTY (this process has one)"

      it "allows only one live owner and does not release a newer owner's lease" do
        first = Termisu.new(sync_updates: false)

        expect_raises(Termisu::TerminalInUseError, "already controlled") do
          Termisu.new(sync_updates: false)
        end
        # A failed acquisition must not release the first instance's lease.
        expect_raises(Termisu::TerminalInUseError) do
          Termisu.new(sync_updates: false)
        end

        first.close
        second = Termisu.new(sync_updates: false)
        Termisu::Logging.configured?.should be_true
        successor_backend = Termisu::Logging.backend
        successor_log_file = Termisu::Logging.log_file

        # Concurrent stale closes must neither release the second instance's
        # lease nor tear down its process-global logging backend.
        stale_closers = [] of Thread
        8.times { stale_closers << Thread.new { first.close } }
        stale_closers.each(&.join)
        Termisu::Logging.configured?.should be_true
        Termisu::Logging.backend.should be(successor_backend)
        Termisu::Logging.log_file.should be(successor_log_file)
        successor_log_file.try(&.closed?.should be_false)
        Termisu::Log.info { "Successor logging remains usable after stale closes" }
        expect_raises(Termisu::TerminalInUseError) do
          Termisu.new(sync_updates: false)
        end

        second.close
        third = Termisu.new(sync_updates: false)
        third.close
      ensure
        first.try(&.close)
        second.try(&.close)
        third.try(&.close)
      end

      it "rolls back sources and terminal state without replacing the startup failure" do
        LifecycleEventLoop.fail_start = true
        LifecycleTerminal.fail_close = true

        expect_raises(Exception, "source startup failed") do
          LifecycleTermisu.new(sync_updates: false)
        end

        terminal = LifecycleTermisu.last_terminal || fail "terminal was not built"
        event_loop = LifecycleTermisu.last_event_loop || fail "event loop was not built"
        terminal.closed?.should be_true
        terminal.raw_mode?.should be_false
        event_loop.running?.should be_false
        event_loop.stop_calls.should eq(1)
      ensure
        LifecycleEventLoop.fail_start = false
        LifecycleTerminal.fail_close = false
      end
    else
      it "raises IO::Error without a controlling TTY" do
        expect_raises(IO::Error) do
          Termisu.new
        end
      end
    end

    it "releases ownership when construction fails" do
      previous_term = ENV["TERM"]?
      ENV.delete("TERM")

      2.times do
        expect_raises(Termisu::Error, "TERM environment variable not set") do
          Termisu.new
        end
      end
    ensure
      if previous_term
        ENV["TERM"] = previous_term
      else
        ENV.delete("TERM")
      end
    end
  end

  describe "#close" do
    it "does not restart input when close begins during raw lease release" do
      read_fd, write_fd = create_pipe
      reader = Termisu::Reader.new(read_fd)
      parser = Termisu::Input::Parser.new(reader)
      input_source = CloseDuringRestartInputSource.new(reader, parser)
      resize_source = Termisu::Event::Source::Resize.new(-> { {80, 24} })
      event_loop = Termisu::Event::Loop.new
      terminal = CaptureTerminal.new(sync_updates: false)
      termisu = Termisu.new(terminal, reader, parser, input_source, resize_source, event_loop)
      event_loop.add_source(input_source).start

      input_source.close_during_next_start(termisu)
      termisu.with_raw_input { }
      input_source.wait_for_close

      event_loop.running?.should be_false
      event_loop.output.closed?.should be_true
      input_source.running?.should be_false
    ensure
      termisu.try &.close
      LibC.close(read_fd) if read_fd
      LibC.close(write_fd) if write_fd
    end

    it "waits for an active mode scope and rejects queued scopes" do
      read_fd, write_fd = create_pipe
      reader = Termisu::Reader.new(read_fd)
      parser = Termisu::Input::Parser.new(reader)
      input_source = PausableInputSource.new(reader, parser)
      resize_source = Termisu::Event::Source::Resize.new(-> { {80, 24} })
      event_loop = Termisu::Event::Loop.new
      terminal = CaptureTerminal.new(sync_updates: false)
      terminal.mode = Termisu::Terminal::Mode.raw
      termisu = Termisu.new(terminal, reader, parser, input_source, resize_source, event_loop)
      event_loop.add_source(input_source).start

      active_entered = Channel(Nil).new
      release_active = Channel(Nil).new
      active_done = Channel(Exception?).new(1)
      queued_started = Channel(Nil).new
      queued_ran = Atomic(Bool).new(false)
      queued_done = Channel(Exception?).new(1)
      close_done = Channel(Exception?).new(1)

      spawn do
        error = nil.as(Exception?)
        begin
          termisu.with_cooked_mode(preserve_screen: true) do
            active_entered.send(nil)
            release_active.receive
          end
        rescue ex
          error = ex
        ensure
          active_done.send(error)
        end
      end
      active_entered.receive

      spawn do
        error = nil.as(Exception?)
        begin
          queued_started.send(nil)
          termisu.with_password_mode(preserve_screen: true) do
            queued_ran.set(true)
          end
        rescue ex
          error = ex
        ensure
          queued_done.send(error)
        end
      end
      queued_started.receive
      Fiber.yield

      spawn do
        error = nil.as(Exception?)
        begin
          termisu.close
        rescue ex
          error = ex
        ensure
          close_done.send(error)
        end
      end
      until termisu.@closed.get
        Fiber.yield
      end

      select
      when close_done.receive
        fail "close returned before the active mode scope restored"
      else
      end

      release_active.send(nil)
      active_done.receive.should be_nil
      queued_done.receive.should be_a(Termisu::Error)
      queued_ran.get.should be_false
      close_done.receive.should be_nil
      # One transition stop plus Event::Loop's idempotent shutdown stop.
      input_source.stop_count.should eq(2)
      input_source.start_count.should eq(1)
      event_loop.output.closed?.should be_true
    ensure
      termisu.try &.close
      reader.try &.close
      LibC.close(read_fd) if read_fd
      LibC.close(write_fd) if write_fd
    end

    it "releases the mode barrier before joining an event source queued on it" do
      read_fd, write_fd = create_pipe
      reader = Termisu::Reader.new(read_fd)
      parser = Termisu::Input::Parser.new(reader)
      input_source = PausableInputSource.new(reader, parser)
      resize_source = Termisu::Event::Source::Resize.new(-> { {80, 24} })
      joining_source = JoiningModeSource.new
      event_loop = Termisu::Event::Loop.new
      terminal = CaptureTerminal.new(sync_updates: false)
      terminal.mode = Termisu::Terminal::Mode.raw
      termisu = Termisu.new(terminal, reader, parser, input_source, resize_source, event_loop)
      joining_source.termisu = termisu
      event_loop.add_source(input_source).add_source(joining_source).start

      active_entered = Channel(Nil).new
      release_active = Channel(Nil).new
      active_done = Channel(Exception?).new(1)
      close_done = Channel(Exception?).new(1)

      spawn do
        error = nil.as(Exception?)
        begin
          termisu.with_cooked_mode(preserve_screen: true) do
            active_entered.send(nil)
            release_active.receive
          end
        rescue ex
          error = ex
        ensure
          active_done.send(error)
        end
      end
      active_entered.receive

      spawn do
        error = nil.as(Exception?)
        begin
          termisu.close
        rescue ex
          error = ex
        ensure
          close_done.send(error)
        end
      end
      until termisu.@closed.get
        Fiber.yield
      end

      # Queue the source behind close while the first scope still owns the gate.
      # Its synchronous stop will join this same worker.
      joining_source.enter_mode
      Fiber.yield
      release_active.send(nil)
      active_done.receive.should be_nil

      select
      when error = close_done.receive
        error.should be_nil
      when timeout(2.seconds)
        fail "close retained the mode gate while joining its event source"
      end
      event_loop.output.closed?.should be_true
    ensure
      termisu.try &.close
      reader.try &.close
      LibC.close(read_fd) if read_fd
      LibC.close(write_fd) if write_fd
    end

    it "rejects same-fiber close before teardown and restores the scope" do
      read_fd, write_fd = create_pipe
      reader = Termisu::Reader.new(read_fd)
      parser = Termisu::Input::Parser.new(reader)
      input_source = PausableInputSource.new(reader, parser)
      resize_source = Termisu::Event::Source::Resize.new(-> { {80, 24} })
      event_loop = Termisu::Event::Loop.new
      terminal = CaptureTerminal.new(sync_updates: false)
      terminal.mode = Termisu::Terminal::Mode.raw
      termisu = Termisu.new(terminal, reader, parser, input_source, resize_source, event_loop)
      event_loop.add_source(input_source).start

      termisu.with_cooked_mode(preserve_screen: true) do
        expect_raises(Termisu::Error, "cannot close Termisu from inside") do
          termisu.close
        end
        termisu.current_mode.should eq(Termisu::Terminal::Mode.cooked)
        termisu.@closed.get.should be_false
      end

      termisu.current_mode.should eq(Termisu::Terminal::Mode.raw)
      input_source.running?.should be_true
      termisu.close
      event_loop.output.closed?.should be_true
    ensure
      termisu.try &.close
      reader.try &.close
      LibC.close(read_fd) if read_fd
      LibC.close(write_fd) if write_fd
    end

    it "preserves the first failure while completing cleanup and releasing ownership" do
      read_fd, write_fd = create_pipe
      reader = Termisu::Reader.new(read_fd)
      parser = Termisu::Input::Parser.new(reader)
      input_source = PausableInputSource.new(reader, parser)
      resize_source = Termisu::Event::Source::Resize.new(-> { {80, 24} })
      event_loop = FailingStopEventLoop.new
      terminal = FailingCloseTerminal.new(sync_updates: false)
      termisu = Termisu.new(terminal, reader, parser, input_source, resize_source, event_loop)

      expect_raises(IO::Error, "event loop stop failed") do
        termisu.close
      end

      event_loop.stop_count.should eq(1)
      terminal.close_count.should eq(1)
      terminal.closed?.should be_true

      lease = Termisu::TerminalOwnership.acquire
      lease.release
    ensure
      termisu.try &.close
      terminal.try &.close
      reader.try &.close
      lease.try &.release
      LibC.close(read_fd) if read_fd
      LibC.close(write_fd) if write_fd
    end

    if controlling_tty?
      it "ignores logging failures, preserves shutdown errors, and remains idempotent" do
        termisu = LifecycleTermisu.new(sync_updates: false)
        event_loop = LifecycleTermisu.last_event_loop || fail "event loop was not built"
        terminal = LifecycleTermisu.last_terminal || fail "terminal was not built"
        LifecycleEventLoop.fail_stop = true

        with_raising_lifecycle_logs do
          expect_raises(Exception, "event stop failed") { termisu.close }
        end

        terminal.closed?.should be_true
        terminal.raw_mode?.should be_false
        event_loop.stop_calls.should eq(1)

        termisu.close
        event_loop.stop_calls.should eq(1)
      ensure
        LifecycleEventLoop.fail_stop = false
      end
    else
      pending "exercises close failure injection (no controlling TTY)"
    end
  end

  describe "#with_mode" do
    it "serializes crossed cooked and password scopes across fibers" do
      read_fd, write_fd = create_pipe
      reader = Termisu::Reader.new(read_fd)
      parser = Termisu::Input::Parser.new(reader)
      input_source = PausableInputSource.new(reader, parser)
      resize_source = Termisu::Event::Source::Resize.new(-> { {80, 24} })
      event_loop = Termisu::Event::Loop.new
      terminal = CaptureTerminal.new(sync_updates: false)
      terminal.mode = Termisu::Terminal::Mode.raw
      termisu = Termisu.new(terminal, reader, parser, input_source, resize_source, event_loop)
      input_source.start(event_loop.output)

      cooked_entered = Channel(Nil).new
      release_cooked = Channel(Nil).new
      cooked_done = Channel(Exception?).new(1)
      password_started = Channel(Nil).new
      password_entered = Channel(Nil).new(1)
      release_password = Channel(Nil).new
      password_done = Channel(Exception?).new(1)

      spawn do
        error = nil.as(Exception?)
        begin
          termisu.with_cooked_mode(preserve_screen: true) do
            cooked_entered.send(nil)
            release_cooked.receive
            termisu.current_mode.should eq(Termisu::Terminal::Mode.cooked)
          end
        rescue ex
          error = ex
        ensure
          cooked_done.send(error)
        end
      end
      cooked_entered.receive

      spawn do
        error = nil.as(Exception?)
        begin
          password_started.send(nil)
          termisu.with_password_mode(preserve_screen: true) do
            password_entered.send(nil)
            release_password.receive
          end
        rescue ex
          error = ex
        ensure
          password_done.send(error)
        end
      end
      password_started.receive
      Fiber.yield

      termisu.current_mode.should eq(Termisu::Terminal::Mode.cooked)
      input_source.running?.should be_false
      select
      when password_entered.receive
        fail "password scope entered before cooked scope restored"
      else
      end

      release_cooked.send(nil)
      cooked_done.receive.should be_nil
      password_entered.receive
      termisu.current_mode.should eq(Termisu::Terminal::Mode.password)
      release_password.send(nil)
      password_done.receive.should be_nil

      termisu.current_mode.should eq(Termisu::Terminal::Mode.raw)
      input_source.running?.should be_true
      input_source.stop_count.should eq(2)
      input_source.start_count.should eq(3)
    ensure
      termisu.try &.close
      LibC.close(read_fd) if read_fd
      LibC.close(write_fd) if write_fd
    end

    it "pauses input for single and combined non-raw modes, but not raw mode" do
      read_fd, write_fd = create_pipe
      reader = Termisu::Reader.new(read_fd)
      parser = Termisu::Input::Parser.new(reader)
      input_source = PausableInputSource.new(reader, parser)
      resize_source = Termisu::Event::Source::Resize.new(-> { {80, 24} })
      event_loop = Termisu::Event::Loop.new
      terminal = CaptureTerminal.new(sync_updates: false)
      terminal.mode = Termisu::Terminal::Mode.raw
      termisu = Termisu.new(terminal, reader, parser, input_source, resize_source, event_loop)
      input_source.start(event_loop.output)

      modes = {
        Termisu::Terminal::Mode::None                                    => false,
        Termisu::Terminal::Mode::Signals                                 => true,
        Termisu::Terminal::Mode::Echo | Termisu::Terminal::Mode::Signals => true,
      }

      modes.each do |mode, should_pause|
        starts_before = input_source.start_count
        stops_before = input_source.stop_count

        termisu.with_mode(mode, preserve_screen: true) do
          input_source.running?.should eq(!should_pause)
          input_source.stop_count.should eq(stops_before + (should_pause ? 1 : 0))
        end

        input_source.running?.should be_true
        input_source.start_count.should eq(starts_before + (should_pause ? 1 : 0))
      end
    ensure
      termisu.try &.close
      LibC.close(read_fd) if read_fd
      LibC.close(write_fd) if write_fd
    end

    it "keeps input paused until the outer nested non-raw mode exits" do
      read_fd, write_fd = create_pipe
      reader = Termisu::Reader.new(read_fd)
      parser = Termisu::Input::Parser.new(reader)
      input_source = PausableInputSource.new(reader, parser)
      resize_source = Termisu::Event::Source::Resize.new(-> { {80, 24} })
      event_loop = Termisu::Event::Loop.new
      terminal = CaptureTerminal.new(sync_updates: false)
      terminal.mode = Termisu::Terminal::Mode.raw
      termisu = Termisu.new(terminal, reader, parser, input_source, resize_source, event_loop)
      input_source.start(event_loop.output)

      result = termisu.with_mode(Termisu::Terminal::Mode.cooked, preserve_screen: true) do
        input_source.running?.should be_false

        nested_result = termisu.with_mode(
          Termisu::Terminal::Mode.password,
          preserve_screen: true,
        ) do
          input_source.running?.should be_false
          42
        end
        nested_result.should eq(42)

        input_source.running?.should be_false
        input_source.start_count.should eq(1)
        input_source.stop_count.should eq(1)
        "outer result"
      end

      result.should eq("outer result")
      input_source.running?.should be_true
      input_source.start_count.should eq(2)
      input_source.stop_count.should eq(1)

      expect_raises(Exception, "mode block failed") do
        termisu.with_mode(Termisu::Terminal::Mode.cooked, preserve_screen: true) do
          raise "mode block failed"
        end
      end
      termisu.current_mode.should eq(Termisu::Terminal::Mode.raw)
      input_source.running?.should be_true
      input_source.start_count.should eq(3)
      input_source.stop_count.should eq(2)
    ensure
      termisu.try &.close
      LibC.close(read_fd) if read_fd
      LibC.close(write_fd) if write_fd
    end

    it "preserves buffered raw input when an overlapping mode exits" do
      read_fd, write_fd = create_pipe
      reader = Termisu::Reader.new(read_fd)
      parser = Termisu::Input::Parser.new(reader)
      input_source = PausableInputSource.new(reader, parser)
      resize_source = Termisu::Event::Source::Resize.new(-> { {80, 24} })
      event_loop = Termisu::Event::Loop.new
      terminal = CaptureTerminal.new(sync_updates: false)
      terminal.mode = Termisu::Terminal::Mode.raw
      termisu = Termisu.new(terminal, reader, parser, input_source, resize_source, event_loop)
      input_source.start(event_loop.output)

      mode_entered = Channel(Nil).new
      release_mode = Channel(Nil).new
      mode_exited = Channel(Nil).new
      spawn do
        termisu.with_cooked_mode(preserve_screen: true) do
          mode_entered.send(nil)
          release_mode.receive
        end
      ensure
        mode_exited.send(nil)
      end

      mode_entered.receive
      termisu.with_raw_input do
        LibC.write(write_fd, "AB".to_unsafe, 2).should eq(2)
        termisu.peek_byte.should eq('A'.ord.to_u8)

        release_mode.send(nil)
        mode_exited.receive

        termisu.input_available?.should be_true
        termisu.read_bytes(2).should eq("AB".to_slice)
        input_source.stop_count.should eq(1)
        input_source.start_count.should eq(1)
      end

      input_source.stop_count.should eq(1)
      input_source.start_count.should eq(2)
    ensure
      termisu.try &.close
      LibC.close(read_fd) if read_fd
      LibC.close(write_fd) if write_fd
    end

    it "keeps input paused when a mode starts during a raw input lease" do
      read_fd, write_fd = create_pipe
      reader = Termisu::Reader.new(read_fd)
      parser = Termisu::Input::Parser.new(reader)
      input_source = PausableInputSource.new(reader, parser)
      resize_source = Termisu::Event::Source::Resize.new(-> { {80, 24} })
      event_loop = Termisu::Event::Loop.new
      terminal = CaptureTerminal.new(sync_updates: false)
      terminal.mode = Termisu::Terminal::Mode.raw
      termisu = Termisu.new(terminal, reader, parser, input_source, resize_source, event_loop)
      input_source.start(event_loop.output)

      mode_entered = Channel(Nil).new
      release_mode = Channel(Nil).new
      mode_exited = Channel(Nil).new

      termisu.with_raw_input do
        spawn do
          termisu.with_cooked_mode(preserve_screen: true) do
            mode_entered.send(nil)
            release_mode.receive
          end
        ensure
          mode_exited.send(nil)
        end

        mode_entered.receive
        input_source.running?.should be_false
        input_source.stop_count.should eq(1)
      end

      input_source.running?.should be_false
      input_source.start_count.should eq(1)

      release_mode.send(nil)
      mode_exited.receive

      input_source.running?.should be_true
      input_source.start_count.should eq(2)
      input_source.stop_count.should eq(1)
    ensure
      termisu.try &.close
      LibC.close(read_fd) if read_fd
      LibC.close(write_fd) if write_fd
    end
  end

  describe "resize event handling" do
    it "resizes the internal buffer before returning a resize event" do
      termisu = Termisu.new(sync_updates: false)

      begin
        initial_width, initial_height = termisu.size
        new_width = initial_width + 1
        new_height = initial_height + 1
        target_x = new_width - 1
        target_y = new_height - 1

        termisu.set_cell(target_x, target_y, 'X').should be_false

        resize_event = Termisu::Event::Resize.new(
          new_width,
          new_height,
          initial_width,
          initial_height,
        )
        resize_events = [resize_event] of Termisu::Event::Any
        resize_source = MockSource.new("test-resize", resize_events)
        termisu.add_event_source(resize_source)

        event = termisu.poll_event(100.milliseconds)
        event.should_not be_nil
        event.should be_a(Termisu::Event::Resize)

        resize = event.as(Termisu::Event::Resize)
        resize.width.should eq(new_width)
        resize.height.should eq(new_height)
        resize.old_width.should eq(initial_width)
        resize.old_height.should eq(initial_height)

        termisu.set_cell(target_x, target_y, 'X').should be_true
      ensure
        termisu.try &.close
      end
    end
  end

  # Note: Phase 4 TASK-015 Event::Loop integration tests are below
  # in "Termisu Event::Loop Integration" since full Termisu init requires TTY
end

# Test Event::Loop integration without requiring full Termisu initialization
describe "Termisu Event::Loop Integration" do
  describe "Event::Loop creation pattern" do
    it "creates loop with input and resize sources" do
      # Simulate what Termisu.initialize should do with mocked components
      read_fd, write_fd = create_pipe
      begin
        reader = Termisu::Reader.new(read_fd)
        parser = Termisu::Input::Parser.new(reader)

        # Create sources as Termisu.initialize should
        input_source = Termisu::Event::Source::Input.new(reader, parser)
        resize_source = Termisu::Event::Source::Resize.new(-> { {80, 24} })

        # Create and configure Event::Loop
        event_loop = Termisu::Event::Loop.new
        event_loop.add_source(input_source)
        event_loop.add_source(resize_source)

        # Verify sources are registered
        event_loop.source_names.should eq(["input", "resize"])

        # Start the loop
        event_loop.start
        event_loop.running?.should be_true

        # Cleanup
        event_loop.stop
        reader.close
      ensure
        LibC.close(read_fd)
        LibC.close(write_fd)
      end
    end

    it "timer source is nil by default" do
      # Timer source should be opt-in, not created by default
      read_fd, write_fd = create_pipe
      begin
        reader = Termisu::Reader.new(read_fd)
        parser = Termisu::Input::Parser.new(reader)

        input_source = Termisu::Event::Source::Input.new(reader, parser)
        resize_source = Termisu::Event::Source::Resize.new(-> { {80, 24} })

        event_loop = Termisu::Event::Loop.new
        event_loop.add_source(input_source)
        event_loop.add_source(resize_source)

        # Only input and resize, no timer
        event_loop.source_names.should eq(["input", "resize"])
        event_loop.source_names.includes?("timer").should be_false

        reader.close
      ensure
        LibC.close(read_fd)
        LibC.close(write_fd)
      end
    end

    it "routes events through unified channel" do
      read_fd, write_fd = create_pipe
      begin
        reader = Termisu::Reader.new(read_fd)
        parser = Termisu::Input::Parser.new(reader)

        input_source = Termisu::Event::Source::Input.new(reader, parser)
        resize_source = Termisu::Event::Source::Resize.new(-> { {80, 24} })

        event_loop = Termisu::Event::Loop.new
        event_loop.add_source(input_source)
        event_loop.add_source(resize_source)
        event_loop.start

        # Send input through pipe
        bytes = Bytes['a'.ord.to_u8]
        LibC.write(write_fd, bytes, bytes.size)

        # Receive through Event::Loop's unified channel
        select
        when event = event_loop.output.receive
          event.should be_a(Termisu::Event::Key)
          event.as(Termisu::Event::Key).char.should eq('a')
        when timeout(100.milliseconds)
          fail "Timeout waiting for event through Event::Loop"
        end

        event_loop.stop
        reader.close
      ensure
        LibC.close(read_fd)
        LibC.close(write_fd)
      end
    end
  end

  describe "graceful shutdown order" do
    it "stops event loop before closing reader" do
      read_fd, write_fd = create_pipe
      begin
        reader = Termisu::Reader.new(read_fd)
        parser = Termisu::Input::Parser.new(reader)

        input_source = Termisu::Event::Source::Input.new(reader, parser)
        event_loop = Termisu::Event::Loop.new
        event_loop.add_source(input_source)
        event_loop.start

        # Graceful shutdown: stop loop first
        event_loop.stop
        event_loop.running?.should be_false
        input_source.running?.should be_false

        # Then close reader
        reader.close

        # No errors should occur
        true.should be_true
      ensure
        LibC.close(read_fd)
        LibC.close(write_fd)
      end
    end
  end

  # TASK-017: poll_event tests
  describe "poll_event" do
    it "receives events through channel" do
      read_fd, write_fd = create_pipe
      begin
        reader = Termisu::Reader.new(read_fd)
        parser = Termisu::Input::Parser.new(reader)

        input_source = Termisu::Event::Source::Input.new(reader, parser)
        event_loop = Termisu::Event::Loop.new
        event_loop.add_source(input_source)
        event_loop.start

        # Send input through pipe
        bytes = Bytes['x'.ord.to_u8]
        LibC.write(write_fd, bytes, bytes.size)

        # Poll should receive through channel
        select
        when event = event_loop.output.receive
          event.should be_a(Termisu::Event::Key)
          event.as(Termisu::Event::Key).char.should eq('x')
        when timeout(100.milliseconds)
          fail "Timeout waiting for event"
        end

        event_loop.stop
        reader.close
      ensure
        LibC.close(read_fd)
        LibC.close(write_fd)
      end
    end

    it "returns nil on timeout" do
      read_fd, write_fd = create_pipe
      begin
        reader = Termisu::Reader.new(read_fd)
        parser = Termisu::Input::Parser.new(reader)

        input_source = Termisu::Event::Source::Input.new(reader, parser)
        event_loop = Termisu::Event::Loop.new
        event_loop.add_source(input_source)
        event_loop.start

        # No data written - should timeout
        select
        when event_loop.output.receive
          fail "Should not receive event when no data available"
        when timeout(10.milliseconds)
          # Expected timeout
          true.should be_true
        end

        event_loop.stop
        reader.close
      ensure
        LibC.close(read_fd)
        LibC.close(write_fd)
      end
    end
  end

  describe "try_poll_event" do
    it "returns nil immediately when no event available" do
      read_fd, write_fd = create_pipe
      begin
        reader = Termisu::Reader.new(read_fd)
        parser = Termisu::Input::Parser.new(reader)

        input_source = Termisu::Event::Source::Input.new(reader, parser)
        event_loop = Termisu::Event::Loop.new
        event_loop.add_source(input_source)
        event_loop.start

        # No data - should return nil immediately (non-blocking)
        select
        when event_loop.output.receive
          fail "Should not receive event"
        else
          # This is the expected path - no event available
          true.should be_true
        end

        event_loop.stop
        reader.close
      ensure
        LibC.close(read_fd)
        LibC.close(write_fd)
      end
    end

    it "returns event immediately when available" do
      read_fd, write_fd = create_pipe
      begin
        reader = Termisu::Reader.new(read_fd)
        parser = Termisu::Input::Parser.new(reader)

        input_source = Termisu::Event::Source::Input.new(reader, parser)
        event_loop = Termisu::Event::Loop.new
        event_loop.add_source(input_source)
        event_loop.start

        # Send input through pipe
        bytes = Bytes['z'.ord.to_u8]
        LibC.write(write_fd, bytes, bytes.size)

        # Give fiber a chance to process
        sleep 10.milliseconds

        # Should get event immediately via select/else
        select
        when event = event_loop.output.receive
          event.should be_a(Termisu::Event::Key)
          event.as(Termisu::Event::Key).char.should eq('z')
        else
          fail "Should have received event"
        end

        event_loop.stop
        reader.close
      ensure
        LibC.close(read_fd)
        LibC.close(write_fd)
      end
    end
  end

  # TASK-018: Timer API tests
  describe "Timer API" do
    it "timer is disabled by default" do
      read_fd, write_fd = create_pipe
      begin
        reader = Termisu::Reader.new(read_fd)
        parser = Termisu::Input::Parser.new(reader)

        input_source = Termisu::Event::Source::Input.new(reader, parser)
        resize_source = Termisu::Event::Source::Resize.new(-> { {80, 24} })

        event_loop = Termisu::Event::Loop.new
        event_loop.add_source(input_source)
        event_loop.add_source(resize_source)

        # Should not have timer source
        event_loop.source_names.includes?("timer").should be_false

        reader.close
      ensure
        LibC.close(read_fd)
        LibC.close(write_fd)
      end
    end

    it "enable_timer adds timer source to loop" do
      read_fd, write_fd = create_pipe
      begin
        reader = Termisu::Reader.new(read_fd)
        parser = Termisu::Input::Parser.new(reader)

        input_source = Termisu::Event::Source::Input.new(reader, parser)
        event_loop = Termisu::Event::Loop.new
        event_loop.add_source(input_source)
        event_loop.start

        # Create and add timer
        timer_source = Termisu::Event::Source::Timer.new(interval: 16.milliseconds)
        event_loop.add_source(timer_source)

        event_loop.source_names.includes?("timer").should be_true

        event_loop.stop
        reader.close
      ensure
        LibC.close(read_fd)
        LibC.close(write_fd)
      end
    end

    it "timer emits Tick events at specified interval" do
      event_loop = Termisu::Event::Loop.new
      timer_source = Termisu::Event::Source::Timer.new(interval: 10.milliseconds)
      event_loop.add_source(timer_source)
      event_loop.start

      # Receive tick event
      select
      when event = event_loop.output.receive
        event.should be_a(Termisu::Event::Tick)
        tick = event.as(Termisu::Event::Tick)
        tick.frame.should be >= 0_u64
      when timeout(100.milliseconds)
        fail "Timeout waiting for tick event"
      end

      event_loop.stop
    end

    it "disable_timer removes timer source" do
      read_fd, write_fd = create_pipe
      begin
        reader = Termisu::Reader.new(read_fd)
        parser = Termisu::Input::Parser.new(reader)

        input_source = Termisu::Event::Source::Input.new(reader, parser)
        timer_source = Termisu::Event::Source::Timer.new(interval: 16.milliseconds)

        event_loop = Termisu::Event::Loop.new
        event_loop.add_source(input_source)
        event_loop.add_source(timer_source)
        event_loop.start

        event_loop.source_names.includes?("timer").should be_true

        # Remove timer
        event_loop.remove_source(timer_source)
        event_loop.source_names.includes?("timer").should be_false

        event_loop.stop
        reader.close
      ensure
        LibC.close(read_fd)
        LibC.close(write_fd)
      end
    end

    it "timer_interval can be changed dynamically" do
      timer_source = Termisu::Event::Source::Timer.new(interval: 100.milliseconds)
      timer_source.interval.should eq(100.milliseconds)

      timer_source.interval = 16.milliseconds
      timer_source.interval.should eq(16.milliseconds)
    end
  end

  # TASK-019: Custom Event Source API tests
  describe "Custom Event Source API" do
    it "add_event_source adds custom source to loop" do
      event_loop = Termisu::Event::Loop.new

      # Create a custom source (using MockSource)
      tick = Termisu::Event::Tick.new(0.seconds, 0.seconds, 0_u64)
      events = [tick] of Termisu::Event::Any
      custom_source = MockSource.new("custom", events)

      event_loop.add_source(custom_source)
      event_loop.source_names.includes?("custom").should be_true
    end

    it "remove_event_source removes custom source from loop" do
      event_loop = Termisu::Event::Loop.new

      custom_source = MockSource.new("custom")
      event_loop.add_source(custom_source)
      event_loop.source_names.includes?("custom").should be_true

      event_loop.remove_source(custom_source)
      event_loop.source_names.includes?("custom").should be_false
    end

    it "custom source emits events to loop channel" do
      tick_event = Termisu::Event::Tick.new(
        elapsed: 100.milliseconds,
        delta: 16.milliseconds,
        frame: 42_u64,
      )
      events = [tick_event] of Termisu::Event::Any
      custom_source = MockSource.new("custom", events)

      event_loop = Termisu::Event::Loop.new
      event_loop.add_source(custom_source)
      event_loop.start

      # Custom source should emit its event
      select
      when event = event_loop.output.receive
        event.should be_a(Termisu::Event::Tick)
        event.as(Termisu::Event::Tick).frame.should eq(42_u64)
      when timeout(100.milliseconds)
        fail "Timeout waiting for custom source event"
      end

      event_loop.stop
    end

    it "supports chaining with add_event_source" do
      event_loop = Termisu::Event::Loop.new
      source1 = MockSource.new("source1")
      source2 = MockSource.new("source2")

      # Chain calls should work
      event_loop.add_source(source1).add_source(source2)

      event_loop.source_names.should eq(["source1", "source2"])
    end

    it "supports chaining with remove_event_source" do
      event_loop = Termisu::Event::Loop.new
      source1 = MockSource.new("source1")
      source2 = MockSource.new("source2")

      event_loop.add_source(source1).add_source(source2)

      # Chain removal should work
      event_loop.remove_source(source1).remove_source(source2)

      event_loop.source_names.should be_empty
    end
  end
end
