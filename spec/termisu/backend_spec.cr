require "../spec_helper"

describe Termisu::Renderer do
  describe "abstract interface" do
    it "can be subclassed" do
      renderer = MockRenderer.new
      renderer.should be_a(Termisu::Renderer)
    end

    it "requires write implementation" do
      renderer = MockRenderer.new
      renderer.write("mock")
      renderer.write_calls.should eq(["mock"])
    end

    it "requires flush implementation" do
      renderer = MockRenderer.new
      renderer.flush
      renderer.flush_count.should eq(1)
    end

    it "requires size implementation" do
      renderer = MockRenderer.new
      renderer.size.should eq({80, 24})
    end

    it "requires close implementation" do
      renderer = MockRenderer.new
      renderer.close
      renderer.close_count.should eq(1)
    end
  end
end

describe Termisu::Terminal::Backend do
  describe ".new" do
    it "creates a backend" do
      backend = Termisu::Terminal::Backend.new
      backend.should be_a(Termisu::Terminal::Backend)
    ensure
      backend.try &.close
    end

    it "exposes input and output file descriptors" do
      backend = Termisu::Terminal::Backend.new
      backend.infd.should be >= 0
      backend.outfd.should be >= 0
    ensure
      backend.try &.close
    end
  end

  describe "#write" do
    it "writes data to the terminal" do
      backend = Termisu::Terminal::Backend.new
      # Should not raise
      backend.write("hello")
    ensure
      backend.try &.close
    end

    it "writes escape sequences" do
      backend = Termisu::Terminal::Backend.new
      # Should not raise
      backend.write("\e[2J")
      backend.write("\e[H")
    ensure
      backend.try &.close
    end
  end

  describe "#flush" do
    it "flushes the output buffer" do
      backend = Termisu::Terminal::Backend.new
      backend.write("test")
      # Should not raise
      backend.flush
    ensure
      backend.try &.close
    end
  end

  describe "#raw_mode?" do
    it "returns false initially" do
      backend = Termisu::Terminal::Backend.new
      backend.raw_mode?.should be_false
    ensure
      backend.try &.close
    end

    it "returns true after enabling raw mode" do
      backend = Termisu::Terminal::Backend.new
      backend.enable_raw_mode
      backend.raw_mode?.should be_true
    ensure
      backend.try &.close
    end

    it "returns false after disabling raw mode" do
      backend = Termisu::Terminal::Backend.new
      backend.enable_raw_mode
      backend.disable_raw_mode
      backend.raw_mode?.should be_false
    ensure
      backend.try &.close
    end
  end

  describe "#enable_raw_mode" do
    it "enables raw mode" do
      backend = Termisu::Terminal::Backend.new
      backend.enable_raw_mode
      backend.raw_mode?.should be_true
    ensure
      backend.try &.close
    end

    it "is idempotent" do
      backend = Termisu::Terminal::Backend.new
      backend.enable_raw_mode
      backend.enable_raw_mode
      backend.raw_mode?.should be_true
    ensure
      backend.try &.close
    end
  end

  describe "#disable_raw_mode" do
    it "disables raw mode" do
      backend = Termisu::Terminal::Backend.new
      backend.enable_raw_mode
      backend.disable_raw_mode
      backend.raw_mode?.should be_false
    ensure
      backend.try &.close
    end

    it "is idempotent" do
      backend = Termisu::Terminal::Backend.new
      backend.disable_raw_mode
      backend.disable_raw_mode
      backend.raw_mode?.should be_false
    ensure
      backend.try &.close
    end

    it "does nothing when raw mode is not enabled" do
      backend = Termisu::Terminal::Backend.new
      backend.disable_raw_mode
      backend.raw_mode?.should be_false
    ensure
      backend.try &.close
    end
  end

  describe "#with_raw_mode" do
    it "enables raw mode within block" do
      backend = Termisu::Terminal::Backend.new
      backend.with_raw_mode do
        backend.raw_mode?.should be_true
      end
    ensure
      backend.try &.close
    end

    it "disables raw mode after block" do
      backend = Termisu::Terminal::Backend.new
      backend.with_raw_mode { }
      backend.raw_mode?.should be_false
    ensure
      backend.try &.close
    end

    it "disables raw mode on exception" do
      backend = Termisu::Terminal::Backend.new
      expect_raises(Exception, "test") do
        backend.with_raw_mode do
          raise "test"
        end
      end
      backend.raw_mode?.should be_false
    ensure
      backend.try &.close
    end

    it "returns the block result" do
      backend = Termisu::Terminal::Backend.new
      result = backend.with_raw_mode { 42 }
      result.should eq(42)
    ensure
      backend.try &.close
    end
  end

  describe "#size" do
    it "returns terminal dimensions" do
      backend = Termisu::Terminal::Backend.new
      width, height = backend.size
      # unbuffer may return 0x0, real terminals return positive values
      width.should be >= 0
      height.should be >= 0
    ensure
      backend.try &.close
    end

    it "returns integer dimensions" do
      backend = Termisu::Terminal::Backend.new
      width, height = backend.size
      width.should be_a(Int32)
      height.should be_a(Int32)
    ensure
      backend.try &.close
    end
  end

  describe "#close" do
    it "disables raw mode on close" do
      backend = Termisu::Terminal::Backend.new
      backend.enable_raw_mode
      backend.close
      backend.raw_mode?.should be_false
    end

    it "can be called without enabling raw mode" do
      backend = Termisu::Terminal::Backend.new
      # Should not raise
      backend.close
    end
  end
end
