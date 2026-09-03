require "../spec_helper"

private class FailingAlternateScreenTerminal < CaptureTerminal
  property? fail_next_flush = false

  def flush
    if @fail_next_flush
      @fail_next_flush = false
      raise IO::Error.new("alternate screen flush failed")
    end
    super
  end
end

private class FailingExitFlushTerminal < Termisu::Terminal
  property? fail_next_flush = false
  getter writes = [] of String

  def write(data : String)
    @writes << data
  end

  def flush
    if @fail_next_flush
      @fail_next_flush = false
      raise IO::Error.new("alternate screen exit failed")
    end
  end
end

private class InitializationFailureBackend < Termisu::Terminal::Backend
  getter close_calls : Int32 = 0

  def size : {Int32, Int32}
    raise "size failed"
  end

  def close
    @close_calls += 1
    super
    raise "cleanup failed"
  end
end

private class RecordingCloseBackend < Termisu::Terminal::Backend
  getter close_calls : Int32 = 0

  def close
    @close_calls += 1
    super
  end
end

private class LoggingLifecycleTerminal < Termisu::Terminal
  def write(data : String)
  end

  def flush
  end
end

private class FaultInjectingTerminal < Termisu::Terminal
  getter cleanup_calls = [] of String

  def disable_mouse
    @cleanup_calls << "mouse"
    raise "mouse cleanup failed"
  end

  def disable_enhanced_keyboard
    @cleanup_calls << "keyboard"
    raise "keyboard cleanup failed"
  end

  def disable_bracketed_paste
    @cleanup_calls << "paste"
    raise "paste cleanup failed"
  end

  def exit_alternate_screen
    @cleanup_calls << "screen"
    raise "screen cleanup failed"
  end
end

describe Termisu::Terminal do
  describe ".new" do
    it "opens /dev/tty and provides valid file descriptors" do
      terminal = CaptureTerminal.new
      terminal.infd.should be >= 0
      terminal.outfd.should be >= 0
    ensure
      terminal.try &.close
    end

    it "closes its backend without replacing the initialization failure" do
      backend = InitializationFailureBackend.new

      expect_raises(Exception, "size failed") do
        Termisu::Terminal.new(backend: backend, terminfo: Termisu::Terminfo.new)
      end

      backend.close_calls.should eq(1)
      # Backend close completed despite its injected post-close failure.
      expect_raises(IO::Error) { backend.write("closed") }
    end
  end

  describe "#raw_mode?" do
    it "tracks raw mode state through enable/disable cycle" do
      terminal = CaptureTerminal.new

      terminal.raw_mode?.should be_false

      terminal.enable_raw_mode
      terminal.raw_mode?.should be_true

      terminal.disable_raw_mode
      terminal.raw_mode?.should be_false
    ensure
      terminal.try &.close
    end

    it "is idempotent for both enable and disable" do
      terminal = CaptureTerminal.new

      # Multiple enables should be idempotent
      terminal.enable_raw_mode
      terminal.enable_raw_mode
      terminal.enable_raw_mode
      terminal.raw_mode?.should be_true

      # Multiple disables should be idempotent
      terminal.disable_raw_mode
      terminal.disable_raw_mode
      terminal.disable_raw_mode
      terminal.raw_mode?.should be_false
    ensure
      terminal.try &.close
    end
  end

  describe "#with_raw_mode" do
    it "enables raw mode only within block execution" do
      terminal = CaptureTerminal.new
      terminal.raw_mode?.should be_false

      terminal.with_raw_mode do
        terminal.raw_mode?.should be_true
      end

      terminal.raw_mode?.should be_false
    ensure
      terminal.try &.close
    end

    it "restores state on exception and returns block result" do
      terminal = CaptureTerminal.new

      # Test exception handling
      expect_raises(Exception, "test error") do
        terminal.with_raw_mode { raise "test error" }
      end
      terminal.raw_mode?.should be_false

      # Test return value
      result = terminal.with_raw_mode { 42 }
      result.should eq(42)
    ensure
      terminal.try &.close
    end
  end

  describe "#write and #flush" do
    it "writes data and escape sequences to the terminal" do
      terminal = CaptureTerminal.new
      # Use invisible sequences to avoid polluting test output
      terminal.write("\e7") # Save cursor
      terminal.write("\e8") # Restore cursor
      terminal.flush
    ensure
      terminal.try &.close
    end
  end

  describe "#size" do
    it "returns non-negative integer dimensions" do
      terminal = CaptureTerminal.new
      width, height = terminal.size
      width.should be >= 0
      height.should be >= 0
    ensure
      terminal.try &.close
    end
  end

  describe "#close" do
    it "disables raw mode and can be called multiple times safely" do
      terminal = CaptureTerminal.new
      terminal.enable_raw_mode
      terminal.close
      terminal.raw_mode?.should be_false

      # Multiple closes should be safe
      terminal.close
      terminal.close
    end

    it "restores raw mode and closes descriptors after alternate-screen output fails" do
      terminal = FailingExitFlushTerminal.new(sync_updates: false)
      terminal.enable_raw_mode
      terminal.enter_alternate_screen
      infd = terminal.infd
      outfd = terminal.outfd
      terminal.fail_next_flush = true

      expect_raises(IO::Error, "alternate screen exit failed") do
        terminal.close
      end

      terminal.raw_mode?.should be_false
      LibC.fcntl(infd, LibC::F_GETFL, 0).should eq(-1)
      Errno.value.should eq(Errno::EBADF)
      LibC.fcntl(outfd, LibC::F_GETFL, 0).should eq(-1)
      Errno.value.should eq(Errno::EBADF)

      # Cleanup and descriptor closure are not retried by repeated close.
      terminal.close
    ensure
      terminal.try &.close
    end

    it "attempts every stage and preserves the first failure" do
      backend = RecordingCloseBackend.new
      terminal = FaultInjectingTerminal.new(backend: backend, terminfo: Termisu::Terminfo.new)

      expect_raises(Exception, "mouse cleanup failed") { terminal.close }

      terminal.cleanup_calls.should eq(["mouse", "keyboard", "paste", "screen"])
      backend.close_calls.should eq(1)
      expect_raises(IO::Error) { backend.write("closed") }

      # Cleanup was completed, so repeated close is a no-op even after failure.
      terminal.close
      backend.close_calls.should eq(1)
    end

    it "restores modes and closes the backend when direct logging fails" do
      backend = RecordingCloseBackend.new
      terminal = LoggingLifecycleTerminal.new(backend: backend, terminfo: Termisu::Terminfo.new)
      terminal.enable_raw_mode
      terminal.enter_alternate_screen

      with_raising_lifecycle_logs { terminal.close }

      terminal.raw_mode?.should be_false
      terminal.alternate_screen?.should be_false
      backend.close_calls.should eq(1)
      expect_raises(IO::Error) { backend.write("closed") }

      terminal.close
      backend.close_calls.should eq(1)
    ensure
      terminal.try &.close
    end
  end

  describe "alternate-screen rollback" do
    it "exits a partially-entered alternate screen and preserves the original error" do
      terminal = FailingAlternateScreenTerminal.new(sync_updates: false)
      terminfo = Termisu::Terminfo.new
      terminal.fail_next_flush = true

      expect_raises(IO::Error, "alternate screen flush failed") do
        terminal.enter_alternate_screen
      end

      terminal.alternate_screen?.should be_false
      terminal.output.should contain(terminfo.enter_ca_seq)
      terminal.output.should contain(terminfo.exit_ca_seq)
    ensure
      terminal.try &.close
    end
  end

  describe "lifecycle management" do
    it "handles full lifecycle correctly" do
      terminal = CaptureTerminal.new
      terminal.enable_raw_mode
      terminal.write("\e7\e8") # Save/restore cursor (invisible)
      terminal.flush
      terminal.disable_raw_mode
      terminal.close
    end
  end

  # --- Terminal Mode API Tests ---

  describe "#current_mode" do
    it "returns nil before any mode is set" do
      terminal = CaptureTerminal.new
      terminal.current_mode.should be_nil
    ensure
      terminal.try &.close
    end

    it "returns the mode after set_mode is called" do
      terminal = CaptureTerminal.new
      terminal.mode = Termisu::Terminal::Mode.raw
      terminal.current_mode.should eq(Termisu::Terminal::Mode.raw)
    ensure
      terminal.try &.close
    end
  end

  describe "#set_mode" do
    it "sets raw mode and updates raw_mode? tracking" do
      terminal = CaptureTerminal.new
      terminal.mode = Termisu::Terminal::Mode.raw
      terminal.current_mode.should eq(Termisu::Terminal::Mode.raw)
      terminal.raw_mode?.should be_true
    ensure
      terminal.try &.close
    end

    it "sets cooked mode and updates raw_mode? tracking" do
      terminal = CaptureTerminal.new
      terminal.mode = Termisu::Terminal::Mode.cooked
      terminal.current_mode.should eq(Termisu::Terminal::Mode.cooked)
      terminal.raw_mode?.should be_false
    ensure
      terminal.try &.close
    end

    it "sets cbreak mode" do
      terminal = CaptureTerminal.new
      terminal.mode = Termisu::Terminal::Mode.cbreak
      terminal.current_mode.should eq(Termisu::Terminal::Mode.cbreak)
      terminal.raw_mode?.should be_false
    ensure
      terminal.try &.close
    end

    it "sets password mode" do
      terminal = CaptureTerminal.new
      terminal.mode = Termisu::Terminal::Mode.password
      terminal.current_mode.should eq(Termisu::Terminal::Mode.password)
      terminal.raw_mode?.should be_false
    ensure
      terminal.try &.close
    end

    it "handles mode transitions" do
      terminal = CaptureTerminal.new

      terminal.mode = Termisu::Terminal::Mode.raw
      terminal.raw_mode?.should be_true

      terminal.mode = Termisu::Terminal::Mode.cooked
      terminal.raw_mode?.should be_false

      terminal.mode = Termisu::Terminal::Mode.raw
      terminal.raw_mode?.should be_true
    ensure
      terminal.try &.close
    end
  end

  describe "#with_mode" do
    it "sets mode within block and restores after" do
      terminal = CaptureTerminal.new
      terminal.mode = Termisu::Terminal::Mode.raw
      terminal.raw_mode?.should be_true

      terminal.with_mode(Termisu::Terminal::Mode.cooked) do
        terminal.current_mode.should eq(Termisu::Terminal::Mode.cooked)
        terminal.raw_mode?.should be_false
      end

      terminal.current_mode.should eq(Termisu::Terminal::Mode.raw)
      terminal.raw_mode?.should be_true
    ensure
      terminal.try &.close
    end

    it "restores mode on exception" do
      terminal = CaptureTerminal.new
      terminal.mode = Termisu::Terminal::Mode.raw

      expect_raises(Exception, "test") do
        terminal.with_mode(Termisu::Terminal::Mode.cooked) do
          terminal.raw_mode?.should be_false
          raise "test"
        end
      end

      terminal.current_mode.should eq(Termisu::Terminal::Mode.raw)
      terminal.raw_mode?.should be_true
    ensure
      terminal.try &.close
    end

    it "returns block result" do
      terminal = CaptureTerminal.new
      result = terminal.with_mode(Termisu::Terminal::Mode.cooked) { 42 }
      result.should eq(42)
    ensure
      terminal.try &.close
    end

    it "handles nested with_mode calls" do
      terminal = CaptureTerminal.new
      terminal.mode = Termisu::Terminal::Mode.raw

      terminal.with_mode(Termisu::Terminal::Mode.cooked) do
        terminal.current_mode.should eq(Termisu::Terminal::Mode.cooked)

        terminal.with_mode(Termisu::Terminal::Mode.password) do
          terminal.current_mode.should eq(Termisu::Terminal::Mode.password)
        end

        terminal.current_mode.should eq(Termisu::Terminal::Mode.cooked)
      end

      terminal.current_mode.should eq(Termisu::Terminal::Mode.raw)
    ensure
      terminal.try &.close
    end

    it "serializes crossed scopes and restores all terminal state" do
      terminal = CaptureTerminal.new(sync_updates: false)
      terminal.mode = Termisu::Terminal::Mode.raw
      terminal.enter_alternate_screen
      terminal.enable_mouse
      terminal.enable_bracketed_paste
      terminal.move_cursor(7, 4)
      terminal.hide_cursor

      first_entered = Channel(Nil).new
      release_first = Channel(Nil).new
      first_done = Channel(Exception?).new(1)
      second_started = Channel(Nil).new
      second_entered = Channel(Nil).new(1)
      release_second = Channel(Nil).new
      second_done = Channel(Exception?).new(1)

      spawn do
        error = nil.as(Exception?)
        begin
          terminal.with_mode(Termisu::Terminal::Mode.cooked, preserve_screen: true) do
            first_entered.send(nil)
            release_first.receive
            terminal.current_mode.should eq(Termisu::Terminal::Mode.cooked)
          end
        rescue ex
          error = ex
        ensure
          first_done.send(error)
        end
      end

      first_entered.receive
      spawn do
        error = nil.as(Exception?)
        begin
          second_started.send(nil)
          terminal.with_mode(Termisu::Terminal::Mode.password, preserve_screen: true) do
            second_entered.send(nil)
            release_second.receive
          end
        rescue ex
          error = ex
        ensure
          second_done.send(error)
        end
      end

      # The rendezvous and yield let the second fiber reach the scope gate.
      # It must not change any state until the first scope has restored.
      second_started.receive
      Fiber.yield
      terminal.current_mode.should eq(Termisu::Terminal::Mode.cooked)
      select
      when second_entered.receive
        fail "cross-fiber mode scope entered before the active scope restored"
      else
      end

      release_first.send(nil)
      first_done.receive.should be_nil
      second_entered.receive
      terminal.current_mode.should eq(Termisu::Terminal::Mode.password)
      release_second.send(nil)
      second_done.receive.should be_nil

      terminal.current_mode.should eq(Termisu::Terminal::Mode.raw)
      terminal.alternate_screen?.should be_true
      terminal.mouse_enabled?.should be_true
      terminal.bracketed_paste?.should be_true
      terminal.cursor.x.should eq(7)
      terminal.cursor.y.should eq(4)
      terminal.cursor.visible?.should be_false
    ensure
      terminal.try &.close
    end

    it "lets close finish the active scope and reject a queued scope" do
      terminal = LoggingLifecycleTerminal.new(sync_updates: false)
      terminal.enable_raw_mode
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
          terminal.with_mode(Termisu::Terminal::Mode.cooked, preserve_screen: true) do
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
          terminal.with_mode(Termisu::Terminal::Mode.password, preserve_screen: true) do
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
          terminal.close
        rescue ex
          error = ex
        ensure
          close_done.send(error)
        end
      end
      until terminal.@terminal_closed.get
        Fiber.yield
      end

      select
      when close_done.receive
        fail "close returned before the active mode scope restored"
      else
      end

      release_active.send(nil)
      active_done.receive.should be_nil
      queued_done.receive.should be_a(IO::Error)
      queued_ran.get.should be_false
      close_done.receive.should be_nil
    ensure
      terminal.try &.close
    end

    it "rejects same-fiber close before teardown and restores the scope" do
      terminal = LoggingLifecycleTerminal.new(sync_updates: false)
      terminal.enable_raw_mode

      terminal.with_mode(Termisu::Terminal::Mode.cooked, preserve_screen: true) do
        expect_raises(IO::Error, "cannot close Terminal from inside") do
          terminal.close
        end
        terminal.current_mode.should eq(Termisu::Terminal::Mode.cooked)
        terminal.@terminal_closed.get.should be_false
      end

      terminal.current_mode.should eq(Termisu::Terminal::Mode.raw)
      terminal.@terminal_closed.get.should be_false
      terminal.close
      terminal.@terminal_closed.get.should be_true
    ensure
      terminal.try &.close
    end

    it "defaults to raw mode when no previous mode was set" do
      terminal = CaptureTerminal.new
      terminal.current_mode.should be_nil

      terminal.with_mode(Termisu::Terminal::Mode.cooked) do
        terminal.current_mode.should eq(Termisu::Terminal::Mode.cooked)
      end

      # Should restore to raw mode (default) since no previous mode
      terminal.current_mode.should eq(Termisu::Terminal::Mode.raw)
    ensure
      terminal.try &.close
    end

    it "respects preserve_screen parameter" do
      terminal = CaptureTerminal.new
      # Cannot directly test alternate screen without visible effects,
      # but we verify the method accepts the parameter
      terminal.with_mode(Termisu::Terminal::Mode.cooked, preserve_screen: true) do
        terminal.current_mode.should eq(Termisu::Terminal::Mode.cooked)
      end

      terminal.with_mode(Termisu::Terminal::Mode.cooked, preserve_screen: false) do
        terminal.current_mode.should eq(Termisu::Terminal::Mode.cooked)
      end
    ensure
      terminal.try &.close
    end

    it "switches modes and restores terminal state when direct logging fails" do
      terminal = CaptureTerminal.new(sync_updates: false)
      terminal.enable_raw_mode
      terminal.enter_alternate_screen
      terminal.enable_mouse
      terminal.enable_bracketed_paste

      with_raising_lifecycle_logs do
        terminal.with_mode(Termisu::Terminal::Mode.cooked) do
          terminal.alternate_screen?.should be_false
          terminal.mouse_enabled?.should be_false
          terminal.bracketed_paste?.should be_false
        end
      end

      terminal.raw_mode?.should be_true
      terminal.alternate_screen?.should be_true
      terminal.mouse_enabled?.should be_true
      terminal.bracketed_paste?.should be_true
    ensure
      terminal.try &.close
    end

    it "invalidates after single and combined non-raw modes, but not raw mode" do
      terminal = CaptureTerminal.new(sync_updates: false)
      terminal.set_cell(0, 0, 'X')
      terminal.render

      modes = {
        Termisu::Terminal::Mode::None                                    => false,
        Termisu::Terminal::Mode::Signals                                 => true,
        Termisu::Terminal::Mode::Echo | Termisu::Terminal::Mode::Signals => true,
      }

      modes.each do |mode, should_invalidate|
        terminal.clear_captured
        terminal.with_mode(mode, preserve_screen: true) { }
        terminal.clear_captured
        terminal.render

        terminal.output.includes?("X").should eq(should_invalidate)
      end
    ensure
      terminal.try &.close
    end
  end

  describe "#with_cooked_mode" do
    it "switches to cooked mode within block" do
      terminal = CaptureTerminal.new
      terminal.mode = Termisu::Terminal::Mode.raw

      terminal.with_cooked_mode do
        terminal.current_mode.should eq(Termisu::Terminal::Mode.cooked)
        terminal.raw_mode?.should be_false
      end

      terminal.current_mode.should eq(Termisu::Terminal::Mode.raw)
    ensure
      terminal.try &.close
    end

    it "returns block result" do
      terminal = CaptureTerminal.new
      result = terminal.with_cooked_mode { "hello" }
      result.should eq("hello")
    ensure
      terminal.try &.close
    end

    it "restores mode on exception" do
      terminal = CaptureTerminal.new
      terminal.mode = Termisu::Terminal::Mode.raw

      expect_raises(Exception, "test") do
        terminal.with_cooked_mode { raise "test" }
      end

      terminal.current_mode.should eq(Termisu::Terminal::Mode.raw)
    ensure
      terminal.try &.close
    end
  end

  describe "#with_cbreak_mode" do
    it "switches to cbreak mode within block" do
      terminal = CaptureTerminal.new
      terminal.mode = Termisu::Terminal::Mode.raw

      terminal.with_cbreak_mode do
        terminal.current_mode.should eq(Termisu::Terminal::Mode.cbreak)
      end

      terminal.current_mode.should eq(Termisu::Terminal::Mode.raw)
    ensure
      terminal.try &.close
    end

    it "defaults to preserve_screen true" do
      terminal = CaptureTerminal.new
      # Method accepts no args, which means preserve_screen defaults to true
      terminal.with_cbreak_mode do
        terminal.current_mode.should eq(Termisu::Terminal::Mode.cbreak)
      end
    ensure
      terminal.try &.close
    end
  end

  describe "#with_password_mode" do
    it "switches to password mode within block" do
      terminal = CaptureTerminal.new
      terminal.mode = Termisu::Terminal::Mode.raw

      terminal.with_password_mode do
        terminal.current_mode.should eq(Termisu::Terminal::Mode.password)
      end

      terminal.current_mode.should eq(Termisu::Terminal::Mode.raw)
    ensure
      terminal.try &.close
    end

    it "defaults to preserve_screen true" do
      terminal = CaptureTerminal.new
      terminal.with_password_mode do
        terminal.current_mode.should eq(Termisu::Terminal::Mode.password)
      end
    ensure
      terminal.try &.close
    end
  end

  # --- Render Cache Reset (BUG-006 regression) ---

  describe "render cache reset after mode switch (BUG-006 regression)" do
    it "re-emits foreground color after with_mode resets cache" do
      terminal = CaptureTerminal.new(sync_updates: false)

      # Set foreground - should emit escape sequence
      terminal.foreground = Termisu::Color.red
      terminal.output.should contain("\e[31m")

      # Clear captured and set same color - should NOT emit (cached)
      terminal.clear_captured
      terminal.foreground = Termisu::Color.red
      terminal.output.should_not contain("\e[31m")

      # with_mode resets cache in ensure block
      terminal.with_mode(Termisu::Terminal::Mode.cooked, preserve_screen: true) { }

      # Clear captured output from with_mode itself
      terminal.clear_captured

      # Same foreground color should now re-emit (cache was reset)
      terminal.foreground = Termisu::Color.red
      terminal.output.should contain("\e[31m")
    ensure
      terminal.try &.close
    end

    it "re-emits background color after with_mode resets cache" do
      terminal = CaptureTerminal.new(sync_updates: false)

      # Set background blue (index 4) → \e[44m
      terminal.background = Termisu::Color.blue
      terminal.output.should contain("\e[44m")

      # Cached - same color should not re-emit
      terminal.clear_captured
      terminal.background = Termisu::Color.blue
      terminal.output.should_not contain("\e[44m")

      # with_mode resets cache
      terminal.with_mode(Termisu::Terminal::Mode.cooked, preserve_screen: true) { }
      terminal.clear_captured

      # Should re-emit after cache reset
      terminal.background = Termisu::Color.blue
      terminal.output.should contain("\e[44m")
    ensure
      terminal.try &.close
    end

    it "resets attribute cache after with_mode" do
      terminal = CaptureTerminal.new(sync_updates: false)

      # Enable bold - should emit
      terminal.enable_bold
      initial_count = terminal.writes.size

      # Enable bold again - should NOT emit (cached)
      terminal.enable_bold
      terminal.writes.size.should eq(initial_count)

      # with_mode resets cache
      terminal.with_mode(Termisu::Terminal::Mode.cooked, preserve_screen: true) { }

      # Enable bold after cache reset - should emit again
      pre_count = terminal.writes.size
      terminal.enable_bold
      terminal.writes.size.should be > pre_count
    ensure
      terminal.try &.close
    end

    it "reset_render_state clears all cached style state" do
      terminal = CaptureTerminal.new(sync_updates: false)

      # Set styles to populate cache
      terminal.foreground = Termisu::Color.green
      terminal.background = Termisu::Color.red
      terminal.enable_bold
      terminal.clear_captured

      # Verify all are cached (no re-emission)
      terminal.foreground = Termisu::Color.green
      terminal.background = Termisu::Color.red
      terminal.enable_bold
      terminal.output.should eq("")

      # Reset render state
      terminal.reset_render_state

      # Foreground and background should re-emit
      terminal.foreground = Termisu::Color.green
      terminal.output.should contain("\e[32m") # Green fg

      terminal.background = Termisu::Color.red
      terminal.output.should contain("\e[41m") # Red bg

      # Bold should also re-emit after reset
      terminal.clear_captured
      terminal.enable_bold
      terminal.output.should contain("\e[1m") # Bold SGR
    ensure
      terminal.try &.close
    end
  end

  # --- Synchronized Updates (DEC Mode 2026) ---

  describe "synchronized updates" do
    describe "escape sequence constants" do
      it "defines BSU (Begin Synchronized Update) sequence" do
        Termisu::Terminal::BSU.should eq("\e[?2026h")
      end

      it "defines ESU (End Synchronized Update) sequence" do
        Termisu::Terminal::ESU.should eq("\e[?2026l")
      end
    end

    describe "#sync_updates?" do
      it "defaults to true" do
        terminal = CaptureTerminal.new
        terminal.sync_updates?.should be_true
      ensure
        terminal.try &.close
      end
    end

    describe "#sync_updates=" do
      it "can disable sync updates at runtime" do
        terminal = CaptureTerminal.new
        terminal.sync_updates?.should be_true

        terminal.sync_updates = false
        terminal.sync_updates?.should be_false
      ensure
        terminal.try &.close
      end

      it "can re-enable sync updates at runtime" do
        terminal = CaptureTerminal.new(sync_updates: false)
        terminal.sync_updates?.should be_false

        terminal.sync_updates = true
        terminal.sync_updates?.should be_true
      ensure
        terminal.try &.close
      end
    end

    describe "#hide_cursor" do
      it "hides the cursor" do
        terminal = CaptureTerminal.new
        terminal.hide_cursor
        terminal.cursor.visible?.should be_false
        terminal.show_cursor
        terminal.hide_cursor
        terminal.cursor.visible?.should be_false
      ensure
        terminal.try &.close
      end
    end

    describe "#show_cursor" do
      it "shows the cursor" do
        terminal = CaptureTerminal.new
        terminal.show_cursor
        terminal.cursor.visible?.should be_true
        terminal.hide_cursor
        terminal.show_cursor
        terminal.cursor.visible?.should be_true
      ensure
        terminal.try &.close
      end
    end

    describe "mouse state" do
      it "enables mouse tracking once and flushes once" do
        terminal = CaptureTerminal.new

        terminal.enable_mouse

        terminal.mouse_enabled?.should be_true
        terminal.output.should contain(Termisu::Terminal::MOUSE_ENABLE_SGR)
        terminal.output.should contain(Termisu::Terminal::MOUSE_ENABLE_NORMAL)
        terminal.captured_flush_count.should eq 1
      ensure
        terminal.try &.close
      end

      it "disables mouse tracking once and flushes once" do
        terminal = CaptureTerminal.new
        terminal.enable_mouse
        terminal.clear_captured

        terminal.disable_mouse

        terminal.mouse_enabled?.should be_false
        terminal.output.should contain(Termisu::Terminal::MOUSE_DISABLE_SGR)
        terminal.output.should contain(Termisu::Terminal::MOUSE_DISABLE_NORMAL)
        terminal.captured_flush_count.should eq 1
      ensure
        terminal.try &.close
      end

      # Two flushes now, not one: mouse reporting is turned OFF before the block gets the
      # tty and back ON in the ensure. It has to be — the block hands fd 0 to another
      # program (an external editor, a shell), and with tracking still on the emulator
      # writes `\e[<0;40;12M` into THAT program's stdin on every click. The count is pinned
      # rather than ignored because each flush is a syscall on a hot path; what this asserts
      # is "one for the suspend, one for the restore, and no per-write churn".
      it "suspends mouse for the block and reapplies it after, one flush each way" do
        terminal = CaptureTerminal.new
        terminal.enable_mouse
        terminal.clear_captured

        # Sampled INSIDE the block, which is the only place the contract is observable:
        # what matters is the state of the wire while the child owns the tty. Comparing
        # the two indices after the fact would not pin it — a disable emitted anywhere
        # before the ensure's re-enable satisfies that ordering, including one emitted
        # after the yield, by which point the child has already taken the clicks.
        during = ""
        terminal.with_mode(Termisu::Terminal::Mode.cooked, preserve_screen: true) do
          during = terminal.output
        end

        during.should contain(Termisu::Terminal::MOUSE_DISABLE_SGR)
        during.should contain(Termisu::Terminal::MOUSE_DISABLE_NORMAL)
        during.should_not contain(Termisu::Terminal::MOUSE_ENABLE_SGR)

        terminal.mouse_enabled?.should be_true
        terminal.output.should contain(Termisu::Terminal::MOUSE_ENABLE_SGR)
        terminal.output.should contain(Termisu::Terminal::MOUSE_ENABLE_NORMAL)
        terminal.captured_flush_count.should eq 2
      ensure
        terminal.try &.close
      end

      # The suspend is flag-guarded, so a consumer that never enabled mouse pays nothing for
      # it: no write and no extra flush before the block. The flush count is the assertion
      # because it is what the guard actually controls.
      #
      # NOT asserted: that the wire is free of mouse sequences entirely. It is not, and that
      # predates this change — `apply_terminal_state` calls `apply_mouse_state @mouse_enabled`
      # UNCONDITIONALLY in the restore, so a `false` there still writes 1006l/1000l for a
      # caller that never enabled mouse. Guarding the restore too would change behaviour on a
      # path this fix does not otherwise touch, so it is left alone deliberately.
      it "adds no write and no flush for the suspend when mouse was never enabled" do
        terminal = CaptureTerminal.new
        terminal.clear_captured

        during = ""
        terminal.with_mode(Termisu::Terminal::Mode.cooked, preserve_screen: true) do
          during = terminal.output
        end

        # Sampled inside the block, because the flush count alone does not pin this:
        # a suspend that wrote the disables and skipped the flush would leave the count
        # at 1 and pass. What must hold is that nothing was emitted for a mouse this
        # caller never turned on.
        during.should_not contain(Termisu::Terminal::MOUSE_DISABLE_SGR)
        during.should_not contain(Termisu::Terminal::MOUSE_DISABLE_NORMAL)
        terminal.captured_flush_count.should eq 1
      ensure
        terminal.try &.close
      end

      # Nesting is the case the flag alone got wrong: `suspend_mouse` leaves
      # `@mouse_enabled` true on purpose, so an inner scope's restore used to re-enable
      # reporting while the OUTER block still owned the tty — exactly the leak this
      # whole change exists to prevent, just one level in. Shelling out and prompting
      # for a password inside that shell-out is the real shape of it.
      #
      # Sampled inside the outer block, after the inner one returns: that is the only
      # window where the regression is observable.
      it "keeps mouse suspended after an inner with_mode returns" do
        terminal = CaptureTerminal.new
        terminal.enable_mouse
        terminal.clear_captured

        after_inner = ""
        terminal.with_mode(Termisu::Terminal::Mode.cooked, preserve_screen: true) do
          terminal.with_mode(Termisu::Terminal::Mode.password, preserve_screen: true) { }
          after_inner = terminal.output
        end

        after_inner.should_not contain(Termisu::Terminal::MOUSE_ENABLE_SGR)
        after_inner.should_not contain(Termisu::Terminal::MOUSE_ENABLE_NORMAL)
        # Restored once the outermost scope exits, not before.
        terminal.output.should contain(Termisu::Terminal::MOUSE_ENABLE_SGR)
      ensure
        terminal.try &.close
      end

      # Reporting comes back once, when the outermost scope exits — not once per level.
      # The inner scope does re-send a disable, which is harmless: it is already off, and
      # the restore writes the flag unconditionally either way.
      it "restores mouse exactly once regardless of nesting depth" do
        terminal = CaptureTerminal.new
        terminal.enable_mouse
        terminal.clear_captured

        terminal.with_mode(Termisu::Terminal::Mode.cooked, preserve_screen: true) do
          terminal.with_mode(Termisu::Terminal::Mode.password, preserve_screen: true) { }
        end

        terminal.output.scan(Termisu::Terminal::MOUSE_ENABLE_SGR).size.should eq 1
        terminal.mouse_enabled?.should be_true
      ensure
        terminal.try &.close
      end
    end

    describe "enhanced keyboard state" do
      it "enables enhanced keyboard once and flushes once" do
        terminal = CaptureTerminal.new

        terminal.enable_enhanced_keyboard

        terminal.enhanced_keyboard?.should be_true
        terminal.output.should contain(Termisu::Terminal::KITTY_KEYBOARD_ENABLE)
        terminal.output.should contain(Termisu::Terminal::MODIFY_OTHER_KEYS_ENABLE)
        terminal.captured_flush_count.should eq 1
      ensure
        terminal.try &.close
      end

      it "disables enhanced keyboard once and flushes once" do
        terminal = CaptureTerminal.new
        terminal.enable_enhanced_keyboard
        terminal.clear_captured

        terminal.disable_enhanced_keyboard

        terminal.enhanced_keyboard?.should be_false
        terminal.output.should contain(Termisu::Terminal::KITTY_KEYBOARD_DISABLE)
        terminal.output.should contain(Termisu::Terminal::MODIFY_OTHER_KEYS_DISABLE)
        terminal.captured_flush_count.should eq 1
      ensure
        terminal.try &.close
      end

      it "reapplies enhanced keyboard state after with_mode restore with one consolidated flush" do
        terminal = CaptureTerminal.new
        terminal.enable_enhanced_keyboard
        terminal.clear_captured

        terminal.with_mode(Termisu::Terminal::Mode.cooked, preserve_screen: true) { }

        terminal.enhanced_keyboard?.should be_true
        terminal.output.should contain(Termisu::Terminal::KITTY_KEYBOARD_ENABLE)
        terminal.output.should contain(Termisu::Terminal::MODIFY_OTHER_KEYS_ENABLE)
        terminal.captured_flush_count.should eq 1
      ensure
        terminal.try &.close
      end
    end

    describe "bracketed paste state" do
      it "enables bracketed paste once and flushes once" do
        terminal = CaptureTerminal.new

        terminal.enable_bracketed_paste
        terminal.enable_bracketed_paste

        terminal.bracketed_paste?.should be_true
        terminal.output.should eq(Termisu::Terminal::BRACKETED_PASTE_ENABLE)
        terminal.captured_flush_count.should eq 1
      ensure
        terminal.try &.close
      end

      it "disables bracketed paste once and flushes once" do
        terminal = CaptureTerminal.new
        terminal.enable_bracketed_paste
        terminal.clear_captured

        terminal.disable_bracketed_paste
        terminal.disable_bracketed_paste

        terminal.bracketed_paste?.should be_false
        terminal.output.should eq(Termisu::Terminal::BRACKETED_PASTE_DISABLE)
        terminal.captured_flush_count.should eq 1
      ensure
        terminal.try &.close
      end

      # An enabled mode that outlives the process leaves the user's shell
      # swallowing \e[200~ around every paste.
      it "disables bracketed paste on close" do
        terminal = CaptureTerminal.new
        terminal.enable_bracketed_paste
        terminal.clear_captured

        terminal.close

        terminal.bracketed_paste?.should be_false
        terminal.output.should contain(Termisu::Terminal::BRACKETED_PASTE_DISABLE)
      end

      # with_mode hands the tty to something that never asked for mode 2004,
      # so it must be off for that window and back on afterwards.
      it "turns bracketed paste off for the duration of with_mode and restores it after" do
        terminal = CaptureTerminal.new
        terminal.enable_bracketed_paste
        terminal.clear_captured
        during = ""

        terminal.with_mode(Termisu::Terminal::Mode.cooked, preserve_screen: true) do
          during = terminal.output
        end

        during.should contain(Termisu::Terminal::BRACKETED_PASTE_DISABLE)
        during.should_not contain(Termisu::Terminal::BRACKETED_PASTE_ENABLE)
        terminal.bracketed_paste?.should be_true
        terminal.output.should contain(Termisu::Terminal::BRACKETED_PASTE_ENABLE)
        # The suspend flush is the extra one: the mode has to be off on the
        # wire before the block runs, it cannot wait for the restore flush.
        terminal.captured_flush_count.should eq 2
      ensure
        terminal.try &.close
      end

      # Backward compatibility: mode 2004 must be invisible to every caller
      # that never asked for it, unlike the mouse and keyboard states which are
      # re-asserted unconditionally.
      it "never touches the mode for a caller that did not enable it" do
        terminal = CaptureTerminal.new
        terminal.enable_mouse
        terminal.enable_enhanced_keyboard
        terminal.clear_captured

        terminal.with_mode(Termisu::Terminal::Mode.cooked, preserve_screen: true) { }
        terminal.close

        terminal.bracketed_paste?.should be_false
        terminal.output.should_not contain("2004")
      end

      # The nesting case, mirroring the mouse specs above: clearing `@bracketed_paste`
      # for the duration is what stops an inner scope's restore from putting 2004h back
      # while the OUTER block still owns the tty. Shelling out and prompting for a
      # password inside that shell-out is the real shape of it.
      #
      # Sampled inside the outer block, after the inner one returns — the only window
      # where the regression is observable.
      it "keeps bracketed paste suspended after an inner with_mode returns" do
        terminal = CaptureTerminal.new
        terminal.enable_bracketed_paste
        terminal.clear_captured

        after_inner = ""
        terminal.with_mode(Termisu::Terminal::Mode.cooked, preserve_screen: true) do
          terminal.with_mode(Termisu::Terminal::Mode.password, preserve_screen: true) { }
          after_inner = terminal.output
        end

        after_inner.should_not contain(Termisu::Terminal::BRACKETED_PASTE_ENABLE)
        # Restored once the outermost scope exits, not before.
        terminal.output.should contain(Termisu::Terminal::BRACKETED_PASTE_ENABLE)
      ensure
        terminal.try &.close
      end

      # Comes back once, when the outermost scope exits — not once per level.
      it "restores bracketed paste exactly once regardless of nesting depth" do
        terminal = CaptureTerminal.new
        terminal.enable_bracketed_paste
        terminal.clear_captured

        terminal.with_mode(Termisu::Terminal::Mode.cooked, preserve_screen: true) do
          terminal.with_mode(Termisu::Terminal::Mode.password, preserve_screen: true) { }
        end

        terminal.output.scan(Termisu::Terminal::BRACKETED_PASTE_ENABLE).size.should eq 1
        terminal.bracketed_paste?.should be_true
      ensure
        terminal.try &.close
      end

      # The desync the guard would otherwise create. A block that enables the mode while
      # it was off outside leaves 2004h on the wire, and the restore is about to record
      # the flag as false — after which the guarded `disable_bracketed_paste` and `close`
      # can never clear it and the mode outlives the process. The disable has to be
      # emitted here, where the discrepancy is still visible.
      it "clears the mode a block turned on while it was off outside" do
        terminal = CaptureTerminal.new
        terminal.clear_captured

        terminal.with_mode(Termisu::Terminal::Mode.cooked, preserve_screen: true) do
          terminal.enable_bracketed_paste
        end

        terminal.bracketed_paste?.should be_false
        terminal.output.should contain(Termisu::Terminal::BRACKETED_PASTE_DISABLE)
        # The library's view and the terminal's agree again: the last 2004 byte on the
        # wire is the disable, not the block's enable.
        terminal.output.rindex!(Termisu::Terminal::BRACKETED_PASTE_DISABLE)
          .should be > terminal.output.rindex!(Termisu::Terminal::BRACKETED_PASTE_ENABLE)
      ensure
        terminal.try &.close
      end
    end

    describe "#title=" do
      it "writes the title when it changes" do
        terminal = CaptureTerminal.new

        terminal.title = "Termisu"

        terminal.title.should eq "Termisu"
        terminal.output.should contain("Termisu")
      ensure
        terminal.try &.close
      end

      it "does nothing when the title is unchanged" do
        terminal = CaptureTerminal.new
        terminal.title = "Termisu"
        terminal.clear_captured

        terminal.title = "Termisu"

        terminal.output.should be_empty
      ensure
        terminal.try &.close
      end
    end

    describe "#move_cursor" do
      it "defaults at 0, 0" do
        terminal = CaptureTerminal.new
        terminal.cursor.x.should eq 0
        terminal.cursor.y.should eq 0
      ensure
        terminal.try &.close
      end

      it "does not move when no arguments" do
        terminal = CaptureTerminal.new
        terminal.move_cursor
        terminal.cursor.x.should eq 0
        terminal.cursor.y.should eq 0
      ensure
        terminal.try &.close
      end

      it "moves the cursor to the specified position on the default terminal size" do
        terminal = CaptureTerminal.new
        terminal.move_cursor(10, 10)
        terminal.cursor.x.should eq 10
        terminal.cursor.y.should eq 10
      ensure
        terminal.try &.close
      end

      it "keeps the current position when called without arguments" do
        terminal = CaptureTerminal.new
        terminal.move_cursor(10, 10)
        terminal.move_cursor
        terminal.cursor.x.should eq 10
        terminal.cursor.y.should eq 10
      ensure
        terminal.try &.close
      end

      it "does not move beyond the default terminal size" do
        terminal = CaptureTerminal.new
        terminal.move_cursor(100, 100)
        terminal.cursor.x.should eq 79
        terminal.cursor.y.should eq 23
      ensure
        terminal.try &.close
      end

      it "moves the cursor into bounds after resize" do
        terminal = CaptureTerminal.new
        terminal.move_cursor(100, 100)
        terminal.size = {10, 10}
        terminal.move_cursor
        terminal.cursor.x.should eq 9
        terminal.cursor.y.should eq 9
      ensure
        terminal.try &.close
      end

      it "does not move the cursor after size increase" do
        terminal = CaptureTerminal.new
        terminal.move_cursor(100, 100)
        terminal.size = {10, 10}
        terminal.move_cursor
        terminal.size = {100, 100}
        terminal.move_cursor
        terminal.cursor.x.should eq 9
        terminal.cursor.y.should eq 9
      ensure
        terminal.try &.close
      end

      it "moves the cursor to the specified position with a larger terminal size" do
        terminal = CaptureTerminal.new
        terminal.size = {100, 100}
        terminal.move_cursor(50, 50)
        terminal.cursor.x.should eq 50
        terminal.cursor.y.should eq 50
      ensure
        terminal.try &.close
      end

      it "does not move beyond a custom terminal size" do
        terminal = CaptureTerminal.new
        terminal.size = {10, 10}
        terminal.move_cursor(50, 50)
        terminal.cursor.x.should eq 9
        terminal.cursor.y.should eq 9
      ensure
        terminal.try &.close
      end

      it "preserves logical cursor position when terminal size is zero" do
        terminal = CaptureTerminal.new
        terminal.move_cursor(10, 10)
        terminal.size = {0, 0}

        terminal.move_cursor

        terminal.cursor.x.should eq 10
        terminal.cursor.y.should eq 10
      ensure
        terminal.try &.close
      end
    end
  end
end
