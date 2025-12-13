require "../spec_helper"

describe Termisu::Reader do
  describe "#clear_buffer and #close" do
    it "are safe to call multiple times" do
      reader = Termisu::Reader.new(0) # stdin
      reader.clear_buffer
      reader.clear_buffer
      reader.close
      reader.close
      reader.close
    end
  end

  describe "#available? and #wait_for_data" do
    it "work with TTY file descriptor" do
      terminal = Termisu::Terminal.new
      reader = Termisu::Reader.new(terminal.infd)

      # available? returns boolean
      reader.available?.should be_a(Bool)

      # wait_for_data returns false on timeout when no input
      reader.wait_for_data(1).should be_false

      # Zero timeout also works
      reader.wait_for_data(0).should be_a(Bool)

      reader.close
      terminal.close
    end

    it "handles full lifecycle" do
      terminal = Termisu::Terminal.new
      reader = Termisu::Reader.new(terminal.infd)
      reader.available?
      reader.clear_buffer
      reader.close
      terminal.close
    end
  end

  # Note: Blocking read operations (read_byte, peek_byte, read_bytes) are tested
  # interactively in examples/demo.cr to avoid
  # blocking spec execution. These methods call LibC.read() which blocks
  # waiting for input even in non-interactive environments.

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

  describe "EINTR handling" do
    # Note: Direct EINTR testing requires signal injection which is complex.
    # The implementation retries on EINTR up to MAX_EINTR_RETRIES times.
    # To verify manually: run a program using Reader and send SIGALRM during I/O.

    it "has reasonable retry limit and proper error types" do
      Termisu::Reader::MAX_EINTR_RETRIES.should be > 0

      error = Termisu::IOError.select_failed(Errno::EBADF)
      error.should be_a(Termisu::IOError)
      error.errno.should eq(Errno::EBADF)
    end
  end
end
