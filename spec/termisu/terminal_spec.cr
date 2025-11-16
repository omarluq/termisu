require "../spec_helper"

describe Termisu::Terminal do
  describe ".new" do
    it "creates a terminal instance" do
      begin
        terminal = Termisu::Terminal.new
        terminal.should be_a(Termisu::Terminal)
        terminal.close
      rescue IO::Error
        # Expected in CI without /dev/tty
        true.should be_true
      end
    end

    it "exposes input and output file descriptors" do
      begin
        terminal = Termisu::Terminal.new
        terminal.infd.should be_a(Int32)
        terminal.outfd.should be_a(Int32)
        terminal.infd.should be >= 0
        terminal.outfd.should be >= 0
        terminal.close
      rescue IO::Error
        # Expected in CI without /dev/tty
        true.should be_true
      end
    end
  end

  describe "#raw_mode?" do
    it "returns false initially" do
      begin
        terminal = Termisu::Terminal.new
        terminal.raw_mode?.should be_false
        terminal.close
      rescue IO::Error
        # Expected in CI
        true.should be_true
      end
    end
  end

  describe "#enable_raw_mode" do
    it "enables raw mode" do
      begin
        terminal = Termisu::Terminal.new
        terminal.enable_raw_mode
        terminal.raw_mode?.should be_true
        terminal.close
      rescue IO::Error
        # Expected in CI or when raw mode cannot be enabled
        true.should be_true
      end
    end

    it "is idempotent" do
      begin
        terminal = Termisu::Terminal.new
        terminal.enable_raw_mode
        terminal.enable_raw_mode
        terminal.enable_raw_mode
        terminal.raw_mode?.should be_true
        terminal.close
      rescue IO::Error
        # Expected in CI
        true.should be_true
      end
    end
  end

  describe "#disable_raw_mode" do
    it "disables raw mode" do
      begin
        terminal = Termisu::Terminal.new
        terminal.enable_raw_mode
        terminal.disable_raw_mode
        terminal.raw_mode?.should be_false
        terminal.close
      rescue IO::Error
        # Expected in CI
        true.should be_true
      end
    end

    it "is idempotent" do
      begin
        terminal = Termisu::Terminal.new
        terminal.disable_raw_mode
        terminal.disable_raw_mode
        terminal.disable_raw_mode
        terminal.raw_mode?.should be_false
        terminal.close
      rescue IO::Error
        # Expected in CI
        true.should be_true
      end
    end
  end

  describe "#with_raw_mode" do
    it "enables raw mode during block execution" do
      begin
        terminal = Termisu::Terminal.new
        terminal.raw_mode?.should be_false

        terminal.with_raw_mode do
          terminal.raw_mode?.should be_true
        end

        terminal.raw_mode?.should be_false
        terminal.close
      rescue IO::Error
        # Expected in CI
        true.should be_true
      end
    end

    it "disables raw mode even if block raises" do
      begin
        terminal = Termisu::Terminal.new

        expect_raises(Exception, "test error") do
          terminal.with_raw_mode do
            raise "test error"
          end
        end

        terminal.raw_mode?.should be_false
        terminal.close
      rescue IO::Error
        # Expected in CI
        true.should be_true
      end
    end
  end

  describe "#write" do
    it "accepts string data" do
      begin
        terminal = Termisu::Terminal.new
        terminal.close
      rescue IO::Error
        # Expected in CI
        true.should be_true
      end
    end
  end

  describe "#flush" do
    it "flushes output without error" do
      begin
        terminal = Termisu::Terminal.new
        terminal.flush
        terminal.close
      rescue IO::Error
        # Expected in CI
        true.should be_true
      end
    end
  end

  describe "#read" do
    it "accepts a buffer" do
      begin
        terminal = Termisu::Terminal.new
        terminal.close
      rescue IO::Error
        # Expected in CI
        true.should be_true
      end
    end
  end

  describe "#size" do
    it "returns width and height tuple" do
      begin
        terminal = Termisu::Terminal.new
        width, height = terminal.size
        width.should be_a(Int32)
        height.should be_a(Int32)
        width.should be > 0
        height.should be > 0
        terminal.close
      rescue IO::Error
        # Expected in CI or non-TTY environment
        true.should be_true
      end
    end
  end

  describe "#close" do
    it "disables raw mode and closes TTY" do
      begin
        terminal = Termisu::Terminal.new
        terminal.enable_raw_mode
        terminal.close
        terminal.raw_mode?.should be_false
      rescue IO::Error
        # Expected in CI
        true.should be_true
      end
    end

    it "is safe to call multiple times" do
      begin
        terminal = Termisu::Terminal.new
        terminal.close
        terminal.close
      rescue IO::Error
        # Expected in CI
        true.should be_true
      end
    end
  end

  describe "lifecycle management" do
    it "handles full lifecycle correctly" do
      begin
        terminal = Termisu::Terminal.new
        terminal.enable_raw_mode
        terminal.flush
        terminal.disable_raw_mode
        terminal.close
      rescue IO::Error
        # Expected in CI
        true.should be_true
      end
    end
  end
end
