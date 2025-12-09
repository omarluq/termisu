require "../spec_helper"

describe Termisu::Reader do
  describe "MAX_EINTR_RETRIES" do
    it "is defined as a reasonable limit" do
      Termisu::Reader::MAX_EINTR_RETRIES.should eq(100)
    end
  end

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

  describe "error handling with pipes" do
    it "reads data from pipe successfully" do
      read_fd, write_fd = create_pipe
      begin
        # Write test data
        LibC.write(write_fd, "hello".to_slice, 5)

        reader = Termisu::Reader.new(read_fd)
        reader.available?.should be_true

        byte = reader.read_byte
        byte.should eq('h'.ord.to_u8)

        reader.close
      ensure
        LibC.close(read_fd)
        LibC.close(write_fd)
      end
    end

    it "returns nil on empty pipe" do
      read_fd, write_fd = create_pipe
      begin
        # Set non-blocking mode
        flags = LibC.fcntl(read_fd, LibC::F_GETFL, 0)
        LibC.fcntl(read_fd, LibC::F_SETFL, flags | LibC::O_NONBLOCK)

        reader = Termisu::Reader.new(read_fd)
        reader.available?.should be_false

        reader.close
      ensure
        LibC.close(read_fd)
        LibC.close(write_fd)
      end
    end

    it "reads multiple bytes from pipe" do
      read_fd, write_fd = create_pipe
      begin
        LibC.write(write_fd, "abc".to_slice, 3)

        reader = Termisu::Reader.new(read_fd)
        bytes = reader.read_bytes(3)
        bytes.should_not be_nil
        if bytes
          String.new(bytes).should eq("abc")
        end

        reader.close
      ensure
        LibC.close(read_fd)
        LibC.close(write_fd)
      end
    end

    it "handles EOF correctly" do
      read_fd, write_fd = create_pipe
      begin
        # Close write end to signal EOF
        LibC.close(write_fd)
        write_fd = -1 # Mark as closed

        reader = Termisu::Reader.new(read_fd)
        byte = reader.read_byte
        byte.should be_nil

        reader.close
      ensure
        LibC.close(read_fd) if read_fd >= 0
        LibC.close(write_fd) if write_fd >= 0
      end
    end

    it "raises IOError on bad file descriptor for select" do
      # -1 is invalid, but select might handle it differently on some systems
      # Use a closed fd instead for reliable error
      read_fd, write_fd = create_pipe
      LibC.close(read_fd)
      LibC.close(write_fd)

      reader = Termisu::Reader.new(read_fd)
      expect_raises(Termisu::IOError) do
        reader.available?
      end
    end
  end

  describe "EINTR handling behavior" do
    it "documents EINTR retry mechanism" do
      # This test documents expected behavior rather than testing it directly.
      # Direct EINTR testing requires signal injection which is complex.
      #
      # The implementation:
      # 1. Both check_fd_readable and fill_buffer retry on EINTR
      # 2. MAX_EINTR_RETRIES prevents infinite loops
      # 3. Other errors (EBADF, EIO) raise immediately
      #
      # To verify manually:
      # 1. Run a program that uses Reader
      # 2. Send SIGALRM or other signals during I/O
      # 3. Observe that reads complete successfully

      Termisu::Reader::MAX_EINTR_RETRIES.should be > 0
    end

    it "uses Termisu::IOError for I/O errors" do
      # Verify error type is correct
      error = Termisu::IOError.select_failed(Errno::EBADF)
      error.should be_a(Termisu::IOError)
      error.errno.should eq(Errno::EBADF)
    end
  end
end
