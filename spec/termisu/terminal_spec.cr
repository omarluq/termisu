require "../spec_helper"

describe Termisu::Terminal do
  describe ".new" do
    it "creates a terminal instance" do
      terminal = Termisu::Terminal.new
      terminal.should be_a(Termisu::Terminal)
    ensure
      terminal.try &.close
    end

    it "exposes input and output file descriptors" do
      terminal = Termisu::Terminal.new
      terminal.infd.should be >= 0
      terminal.outfd.should be >= 0
    ensure
      terminal.try &.close
    end
  end

  describe "#raw_mode?" do
    it "returns false initially" do
      terminal = Termisu::Terminal.new
      terminal.raw_mode?.should be_false
    ensure
      terminal.try &.close
    end
  end

  describe "#enable_raw_mode" do
    it "enables raw mode" do
      terminal = Termisu::Terminal.new
      terminal.enable_raw_mode
      terminal.raw_mode?.should be_true
    ensure
      terminal.try &.close
    end

    it "is idempotent" do
      terminal = Termisu::Terminal.new
      terminal.enable_raw_mode
      terminal.enable_raw_mode
      terminal.enable_raw_mode
      terminal.raw_mode?.should be_true
    ensure
      terminal.try &.close
    end
  end

  describe "#disable_raw_mode" do
    it "disables raw mode" do
      terminal = Termisu::Terminal.new
      terminal.enable_raw_mode
      terminal.disable_raw_mode
      terminal.raw_mode?.should be_false
    ensure
      terminal.try &.close
    end

    it "is idempotent" do
      terminal = Termisu::Terminal.new
      terminal.disable_raw_mode
      terminal.disable_raw_mode
      terminal.disable_raw_mode
      terminal.raw_mode?.should be_false
    ensure
      terminal.try &.close
    end
  end

  describe "#with_raw_mode" do
    it "enables raw mode during block execution" do
      terminal = Termisu::Terminal.new
      terminal.raw_mode?.should be_false

      terminal.with_raw_mode do
        terminal.raw_mode?.should be_true
      end

      terminal.raw_mode?.should be_false
    ensure
      terminal.try &.close
    end

    it "disables raw mode even if block raises" do
      terminal = Termisu::Terminal.new

      expect_raises(Exception, "test error") do
        terminal.with_raw_mode do
          raise "test error"
        end
      end

      terminal.raw_mode?.should be_false
    ensure
      terminal.try &.close
    end

    it "returns the block result" do
      terminal = Termisu::Terminal.new
      result = terminal.with_raw_mode { 42 }
      result.should eq(42)
    ensure
      terminal.try &.close
    end
  end

  describe "#write" do
    it "writes data to the terminal" do
      terminal = Termisu::Terminal.new
      # Should not raise
      terminal.write("test")
    ensure
      terminal.try &.close
    end

    it "writes escape sequences" do
      terminal = Termisu::Terminal.new
      # Should not raise
      terminal.write("\e[2J")
    ensure
      terminal.try &.close
    end
  end

  describe "#flush" do
    it "flushes output without error" do
      terminal = Termisu::Terminal.new
      terminal.write("test")
      terminal.flush
    ensure
      terminal.try &.close
    end
  end

  describe "#size" do
    it "returns width and height tuple" do
      terminal = Termisu::Terminal.new
      width, height = terminal.size
      width.should be_a(Int32)
      height.should be_a(Int32)
      # unbuffer may return 0x0, real terminals return positive values
      width.should be >= 0
      height.should be >= 0
    ensure
      terminal.try &.close
    end
  end

  describe "#close" do
    it "disables raw mode on close" do
      terminal = Termisu::Terminal.new
      terminal.enable_raw_mode
      terminal.close
      terminal.raw_mode?.should be_false
    end

    it "can be called multiple times safely" do
      terminal = Termisu::Terminal.new
      terminal.close
      terminal.close
    end
  end

  describe "lifecycle management" do
    it "handles full lifecycle correctly" do
      terminal = Termisu::Terminal.new
      terminal.enable_raw_mode
      terminal.write("hello")
      terminal.flush
      terminal.disable_raw_mode
      terminal.close
    end
  end
end
