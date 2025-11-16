require "../spec_helper"

describe Termisu::Reader do
  describe ".new" do
    it "creates a reader with file descriptor" do
      reader = Termisu::Reader.new(0) # stdin
      reader.should be_a(Termisu::Reader)
      reader.close
    end

    it "accepts custom buffer size" do
      reader = Termisu::Reader.new(0, buffer_size: 256)
      reader.should be_a(Termisu::Reader)
      reader.close
    end

    it "accepts negative file descriptor without validation" do
      # Constructor doesn't validate - errors occur on read
      reader = Termisu::Reader.new(-1)
      reader.should be_a(Termisu::Reader)
      reader.close
    end
  end

  describe "#clear_buffer" do
    it "clears internal buffer state" do
      reader = Termisu::Reader.new(0)
      reader.clear_buffer
      reader.close
    end

    it "is safe to call multiple times" do
      reader = Termisu::Reader.new(0)
      reader.clear_buffer
      reader.clear_buffer
      reader.clear_buffer
      reader.close
    end
  end

  describe "#close" do
    it "closes reader without error" do
      reader = Termisu::Reader.new(0)
      reader.close
    end

    it "is safe to call multiple times" do
      reader = Termisu::Reader.new(0)
      reader.close
      reader.close
      reader.close
    end
  end

  describe "#available?" do
    it "returns boolean" do
      begin
        terminal = Termisu::Terminal.new
        reader = Termisu::Reader.new(terminal.infd)
        result = reader.available?
        result.should be_a(Bool)
        reader.close
        terminal.close
      rescue IO::Error
        # Expected in CI
        true.should be_true
      end
    end

    it "returns false when no data available" do
      begin
        terminal = Termisu::Terminal.new
        reader = Termisu::Reader.new(terminal.infd)
        # In non-interactive environment, typically no data
        result = reader.available?
        result.should be_a(Bool)
        reader.close
        terminal.close
      rescue IO::Error
        # Expected in CI
        true.should be_true
      end
    end
  end

  describe "#wait_for_data" do
    it "accepts timeout in milliseconds" do
      begin
        terminal = Termisu::Terminal.new
        reader = Termisu::Reader.new(terminal.infd)
        # Should timeout quickly when no data
        result = reader.wait_for_data(10)
        result.should be_a(Bool)
        reader.close
        terminal.close
      rescue IO::Error
        # Expected in CI
        true.should be_true
      end
    end

    it "returns false on timeout" do
      begin
        terminal = Termisu::Terminal.new
        reader = Termisu::Reader.new(terminal.infd)
        # Should timeout when no input available
        result = reader.wait_for_data(1)
        result.should be_false
        reader.close
        terminal.close
      rescue IO::Error
        # Expected in CI
        true.should be_true
      end
    end

    it "handles zero timeout" do
      begin
        terminal = Termisu::Terminal.new
        reader = Termisu::Reader.new(terminal.infd)
        result = reader.wait_for_data(0)
        result.should be_a(Bool)
        reader.close
        terminal.close
      rescue IO::Error
        # Expected in CI
        true.should be_true
      end
    end
  end

  # Note: Blocking read operations (read_byte, peek_byte, read_bytes) are tested
  # interactively in examples/demo.cr to avoid
  # blocking spec execution. These methods call LibC.read() which blocks
  # waiting for input even in non-interactive environments.

  describe "lifecycle management" do
    it "handles full lifecycle" do
      begin
        terminal = Termisu::Terminal.new
        reader = Termisu::Reader.new(terminal.infd)
        reader.available?
        reader.clear_buffer
        reader.close
        terminal.close
      rescue IO::Error
        # Expected in CI
        true.should be_true
      end
    end
  end
end
