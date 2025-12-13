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
end
