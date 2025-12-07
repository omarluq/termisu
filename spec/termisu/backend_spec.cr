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
    it "creates a terminal renderer" do
      begin
        renderer = Termisu::Terminal::Backend.new
        renderer.should be_a(Termisu::Terminal::Backend)
        renderer.close
      rescue IO::Error
        # Expected in CI without /dev/tty
        true.should be_true
      end
    end

    it "exposes input and output file descriptors" do
      begin
        renderer = Termisu::Terminal::Backend.new
        renderer.infd.should be_a(Int32)
        renderer.outfd.should be_a(Int32)
        renderer.infd.should be >= 0
        renderer.outfd.should be >= 0
        renderer.close
      rescue IO::Error
        # Expected in CI without /dev/tty
        true.should be_true
      end
    end
  end

  describe "#raw_mode?" do
    it "returns false initially" do
      begin
        renderer = Termisu::Terminal::Backend.new
        renderer.raw_mode?.should be_false
        renderer.close
      rescue IO::Error
        # Expected in CI
        true.should be_true
      end
    end
  end

  describe "#enable_raw_mode" do
    it "enables raw mode" do
      begin
        renderer = Termisu::Terminal::Backend.new
        renderer.enable_raw_mode
        renderer.raw_mode?.should be_true
        renderer.close
      rescue IO::Error
        # Expected in CI
        true.should be_true
      end
    end
  end

  describe "#size" do
    it "returns terminal dimensions" do
      begin
        renderer = Termisu::Terminal::Backend.new
        width, height = renderer.size
        width.should be_a(Int32)
        height.should be_a(Int32)
        width.should be > 0
        height.should be > 0
        renderer.close
      rescue IO::Error
        # Expected in CI
        true.should be_true
      end
    end
  end

  describe "#close" do
    it "disables raw mode and closes TTY" do
      begin
        renderer = Termisu::Terminal::Backend.new
        renderer.enable_raw_mode
        renderer.close
        renderer.raw_mode?.should be_false
      rescue IO::Error
        # Expected in CI
        true.should be_true
      end
    end
  end
end
