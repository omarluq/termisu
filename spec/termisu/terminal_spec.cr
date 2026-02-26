require "../spec_helper"

describe Termisu::Terminal do
  describe ".new" do
    it "opens /dev/tty and provides valid file descriptors" do
      terminal = Termisu::Terminal.new
      terminal.infd.should be >= 0
      terminal.outfd.should be >= 0
    ensure
      terminal.try &.close
    end
  end

  describe "#raw_mode?" do
    it "tracks raw mode state through enable/disable cycle" do
      terminal = Termisu::Terminal.new

      terminal.raw_mode?.should be_false

      terminal.enable_raw_mode
      terminal.raw_mode?.should be_true

      terminal.disable_raw_mode
      terminal.raw_mode?.should be_false
    ensure
      terminal.try &.close
    end

    it "is idempotent for both enable and disable" do
      terminal = Termisu::Terminal.new

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
      terminal = Termisu::Terminal.new
      terminal.raw_mode?.should be_false

      terminal.with_raw_mode do
        terminal.raw_mode?.should be_true
      end

      terminal.raw_mode?.should be_false
    ensure
      terminal.try &.close
    end

    it "restores state on exception and returns block result" do
      terminal = Termisu::Terminal.new

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
      terminal = Termisu::Terminal.new
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
      terminal = Termisu::Terminal.new
      width, height = terminal.size
      # unbuffer may return 0x0, real terminals return positive values
      width.should be >= 0
      height.should be >= 0
    ensure
      terminal.try &.close
    end
  end

  describe "#close" do
    it "disables raw mode and can be called multiple times safely" do
      terminal = Termisu::Terminal.new
      terminal.enable_raw_mode
      terminal.close
      terminal.raw_mode?.should be_false

      # Multiple closes should be safe
      terminal.close
      terminal.close
    end
  end

  describe "lifecycle management" do
    it "handles full lifecycle correctly" do
      terminal = Termisu::Terminal.new
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
      terminal = Termisu::Terminal.new
      terminal.current_mode.should be_nil
    ensure
      terminal.try &.close
    end

    it "returns the mode after set_mode is called" do
      terminal = Termisu::Terminal.new
      terminal.set_mode(Termisu::Terminal::Mode.raw)
      terminal.current_mode.should eq(Termisu::Terminal::Mode.raw)
    ensure
      terminal.try &.close
    end
  end

  describe "#set_mode" do
    it "sets raw mode and updates raw_mode? tracking" do
      terminal = Termisu::Terminal.new
      terminal.set_mode(Termisu::Terminal::Mode.raw)
      terminal.current_mode.should eq(Termisu::Terminal::Mode.raw)
      terminal.raw_mode?.should be_true
    ensure
      terminal.try &.close
    end

    it "sets cooked mode and updates raw_mode? tracking" do
      terminal = Termisu::Terminal.new
      terminal.set_mode(Termisu::Terminal::Mode.cooked)
      terminal.current_mode.should eq(Termisu::Terminal::Mode.cooked)
      terminal.raw_mode?.should be_false
    ensure
      terminal.try &.close
    end

    it "sets cbreak mode" do
      terminal = Termisu::Terminal.new
      terminal.set_mode(Termisu::Terminal::Mode.cbreak)
      terminal.current_mode.should eq(Termisu::Terminal::Mode.cbreak)
      terminal.raw_mode?.should be_false
    ensure
      terminal.try &.close
    end

    it "sets password mode" do
      terminal = Termisu::Terminal.new
      terminal.set_mode(Termisu::Terminal::Mode.password)
      terminal.current_mode.should eq(Termisu::Terminal::Mode.password)
      terminal.raw_mode?.should be_false
    ensure
      terminal.try &.close
    end

    it "handles mode transitions" do
      terminal = Termisu::Terminal.new

      terminal.set_mode(Termisu::Terminal::Mode.raw)
      terminal.raw_mode?.should be_true

      terminal.set_mode(Termisu::Terminal::Mode.cooked)
      terminal.raw_mode?.should be_false

      terminal.set_mode(Termisu::Terminal::Mode.raw)
      terminal.raw_mode?.should be_true
    ensure
      terminal.try &.close
    end
  end

  describe "#with_mode" do
    it "sets mode within block and restores after" do
      terminal = Termisu::Terminal.new
      terminal.set_mode(Termisu::Terminal::Mode.raw)
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
      terminal = Termisu::Terminal.new
      terminal.set_mode(Termisu::Terminal::Mode.raw)

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
      terminal = Termisu::Terminal.new
      result = terminal.with_mode(Termisu::Terminal::Mode.cooked) { 42 }
      result.should eq(42)
    ensure
      terminal.try &.close
    end

    it "handles nested with_mode calls" do
      terminal = Termisu::Terminal.new
      terminal.set_mode(Termisu::Terminal::Mode.raw)

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

    it "defaults to raw mode when no previous mode was set" do
      terminal = Termisu::Terminal.new
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
      terminal = Termisu::Terminal.new
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
  end

  describe "#with_cooked_mode" do
    it "switches to cooked mode within block" do
      terminal = Termisu::Terminal.new
      terminal.set_mode(Termisu::Terminal::Mode.raw)

      terminal.with_cooked_mode do
        terminal.current_mode.should eq(Termisu::Terminal::Mode.cooked)
        terminal.raw_mode?.should be_false
      end

      terminal.current_mode.should eq(Termisu::Terminal::Mode.raw)
    ensure
      terminal.try &.close
    end

    it "returns block result" do
      terminal = Termisu::Terminal.new
      result = terminal.with_cooked_mode { "hello" }
      result.should eq("hello")
    ensure
      terminal.try &.close
    end

    it "restores mode on exception" do
      terminal = Termisu::Terminal.new
      terminal.set_mode(Termisu::Terminal::Mode.raw)

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
      terminal = Termisu::Terminal.new
      terminal.set_mode(Termisu::Terminal::Mode.raw)

      terminal.with_cbreak_mode do
        terminal.current_mode.should eq(Termisu::Terminal::Mode.cbreak)
      end

      terminal.current_mode.should eq(Termisu::Terminal::Mode.raw)
    ensure
      terminal.try &.close
    end

    it "defaults to preserve_screen true" do
      terminal = Termisu::Terminal.new
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
      terminal = Termisu::Terminal.new
      terminal.set_mode(Termisu::Terminal::Mode.raw)

      terminal.with_password_mode do
        terminal.current_mode.should eq(Termisu::Terminal::Mode.password)
      end

      terminal.current_mode.should eq(Termisu::Terminal::Mode.raw)
    ensure
      terminal.try &.close
    end

    it "defaults to preserve_screen true" do
      terminal = Termisu::Terminal.new
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
        terminal = Termisu::Terminal.new
        terminal.sync_updates?.should be_true
      ensure
        terminal.try &.close
      end
    end

    describe "#sync_updates=" do
      it "can disable sync updates at runtime" do
        terminal = Termisu::Terminal.new
        terminal.sync_updates?.should be_true

        terminal.sync_updates = false
        terminal.sync_updates?.should be_false
      ensure
        terminal.try &.close
      end

      it "can re-enable sync updates at runtime" do
        terminal = Termisu::Terminal.new(sync_updates: false)
        terminal.sync_updates?.should be_false

        terminal.sync_updates = true
        terminal.sync_updates?.should be_true
      ensure
        terminal.try &.close
      end
    end
  end
end
