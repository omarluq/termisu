require "../spec_helper"

describe Termisu::Renderer do
  describe "abstract interface" do
    it "tracks method calls correctly" do
      renderer = MockRenderer.new

      renderer.write("hello")
      renderer.write("world")
      renderer.flush
      renderer.close

      renderer.write_calls.should eq(["hello", "world"])
      renderer.flush_count.should eq(1)
      renderer.close_count.should eq(1)
      renderer.size.should eq({80, 24})
    end
  end
end

describe Termisu::Terminal::Backend do
  describe ".new" do
    it "opens /dev/tty and provides valid file descriptors" do
      backend = Termisu::Terminal::Backend.new
      backend.infd.should be >= 0
      backend.outfd.should be >= 0
    ensure
      backend.try &.close
    end
  end

  describe "#write and #flush" do
    it "writes data and escape sequences to the terminal" do
      backend = Termisu::Terminal::Backend.new
      # Use invisible sequences to avoid polluting test output
      backend.write("\e7") # Save cursor
      backend.write("\e8") # Restore cursor
      backend.flush
    ensure
      backend.try &.close
    end
  end

  describe "#raw_mode?" do
    it "tracks raw mode state through enable/disable cycle" do
      backend = Termisu::Terminal::Backend.new

      backend.raw_mode?.should be_false

      backend.enable_raw_mode
      backend.raw_mode?.should be_true

      backend.disable_raw_mode
      backend.raw_mode?.should be_false
    ensure
      backend.try &.close
    end

    it "is idempotent for both enable and disable" do
      backend = Termisu::Terminal::Backend.new

      # Multiple enables should be idempotent
      backend.enable_raw_mode
      backend.enable_raw_mode
      backend.enable_raw_mode
      backend.raw_mode?.should be_true

      # Multiple disables should be idempotent
      backend.disable_raw_mode
      backend.disable_raw_mode
      backend.disable_raw_mode
      backend.raw_mode?.should be_false
    ensure
      backend.try &.close
    end
  end

  describe "#with_raw_mode" do
    it "enables raw mode only within block execution" do
      backend = Termisu::Terminal::Backend.new
      backend.raw_mode?.should be_false

      backend.with_raw_mode do
        backend.raw_mode?.should be_true
      end

      backend.raw_mode?.should be_false
    ensure
      backend.try &.close
    end

    it "restores state on exception and returns block result" do
      backend = Termisu::Terminal::Backend.new

      # Test exception handling
      expect_raises(Exception, "test") do
        backend.with_raw_mode { raise "test" }
      end
      backend.raw_mode?.should be_false

      # Test return value
      result = backend.with_raw_mode { 42 }
      result.should eq(42)
    ensure
      backend.try &.close
    end
  end

  describe "#size" do
    it "returns non-negative integer dimensions" do
      backend = Termisu::Terminal::Backend.new
      width, height = backend.size
      # unbuffer may return 0x0, real terminals return positive values
      width.should be >= 0
      height.should be >= 0
    ensure
      backend.try &.close
    end
  end

  describe "#close" do
    it "disables raw mode and can be called multiple times safely" do
      backend = Termisu::Terminal::Backend.new
      backend.enable_raw_mode
      backend.close
      backend.raw_mode?.should be_false

      # Multiple closes should be safe
      backend.close
      backend.close
    end
  end
end
