require "../spec_helper"

# Mock backend for testing abstract interface
class MockBackend < Termisu::Backend
  property write_calls : Array(String) = [] of String
  property flush_called : Int32 = 0
  property close_called : Int32 = 0
  property mock_size : {Int32, Int32} = {80, 24}

  def write(data : String)
    @write_calls << data
  end

  def flush
    @flush_called += 1
  end

  def size : {Int32, Int32}
    @mock_size
  end

  def close
    @close_called += 1
  end
end

describe Termisu::Backend do
  describe "abstract interface" do
    it "can be subclassed" do
      backend = MockBackend.new
      backend.should be_a(Termisu::Backend)
    end

    it "requires write implementation" do
      backend = MockBackend.new
      backend.write("mock")
      backend.write_calls.should eq(["mock"])
    end

    it "requires flush implementation" do
      backend = MockBackend.new
      backend.flush
      backend.flush_called.should eq(1)
    end

    it "requires size implementation" do
      backend = MockBackend.new
      backend.size.should eq({80, 24})
    end

    it "requires close implementation" do
      backend = MockBackend.new
      backend.close
      backend.close_called.should eq(1)
    end
  end
end

describe Termisu::Terminal::Backend do
  describe ".new" do
    it "creates a terminal backend" do
      begin
        terminal = Termisu::Terminal.new
        terminfo = Termisu::Terminfo.new
        backend = Termisu::Terminal::Backend.new(terminal, terminfo)
        backend.should be_a(Termisu::Terminal::Backend)
        backend.should be_a(Termisu::Backend)
        backend.close
      rescue IO::Error | Termisu::Error
        # Expected in CI without /dev/tty or TERM
        true.should be_true
      end
    end
  end

  describe "#size" do
    it "delegates to terminal" do
      begin
        terminal = Termisu::Terminal.new
        terminfo = Termisu::Terminfo.new
        backend = Termisu::Terminal::Backend.new(terminal, terminfo)
        width, height = backend.size
        width.should be_a(Int32)
        height.should be_a(Int32)
        backend.close
      rescue IO::Error | Termisu::Error
        # Expected in CI
        true.should be_true
      end
    end
  end

  describe "#alternate_screen?" do
    it "returns false initially" do
      begin
        terminal = Termisu::Terminal.new
        terminfo = Termisu::Terminfo.new
        backend = Termisu::Terminal::Backend.new(terminal, terminfo)
        backend.alternate_screen?.should be_false
        backend.close
      rescue IO::Error | Termisu::Error
        # Expected in CI
        true.should be_true
      end
    end
  end

  # Note: Terminal manipulation methods (clear_screen, move_cursor, show_cursor,
  # hide_cursor, enter_alternate_screen, exit_alternate_screen, color/attribute
  # methods) are tested interactively in examples/demo.cr to avoid polluting
  # spec output with escape sequences and screen manipulation.

  describe "#close" do
    it "closes underlying terminal" do
      begin
        terminal = Termisu::Terminal.new
        terminfo = Termisu::Terminfo.new
        backend = Termisu::Terminal::Backend.new(terminal, terminfo)
        backend.close
      rescue IO::Error | Termisu::Error
        # Expected in CI
        true.should be_true
      end
    end
  end
end
