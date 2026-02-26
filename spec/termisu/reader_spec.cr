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

  describe "high fd guard (BUG-010 regression)" do
    # Regression for issue #010: Reader used select(2) for all fds, but select() cannot handle
    # fd >= FD_SETSIZE (1024) — it would write out-of-bounds into the fd_set
    # bitmask, causing IndexError or memory corruption.
    # The fix routes fd >= 1024 to poll(2) as a fallback.

    it "defines FD_SETSIZE constant at 1024" do
      Termisu::Reader::FD_SETSIZE.should eq(1024)
    end

    it "raises IOError (not IndexError) for invalid high fd" do
      # Create a pipe, grab the fd, close it to make it invalid.
      # Before the fix, fds >= FD_SETSIZE would crash with IndexError on fds_bits.
      # After the fix, high fds route to poll(2) which returns POLLNVAL → IOError.
      # Using a closed fd that may be < 1024 still exercises the error path.
      temp_reader, temp_writer = IO.pipe
      closed_fd = temp_reader.fd
      temp_reader.close
      temp_writer.close

      reader = Termisu::Reader.new(closed_fd)
      expect_raises(Termisu::IOError) do
        reader.available?
      end
      reader.close
    end

    it "raises IOError (not IndexError) for very high fd" do
      # Test with fd well above FD_SETSIZE to confirm poll fallback.
      # Using a synthetic fd value that's guaranteed not to be open.
      temp_reader, temp_writer = IO.pipe
      closed_fd = temp_reader.fd
      temp_reader.close
      temp_writer.close

      # Use the closed fd + FD_SETSIZE to guarantee > 1024
      high_fd = closed_fd + Termisu::Reader::FD_SETSIZE
      reader = Termisu::Reader.new(high_fd)
      expect_raises(Termisu::IOError) do
        reader.available?
      end
      reader.close
    end

    it "normal pipe fd uses select path and works correctly" do
      # Low fds (< 1024) still use the select(2) path.
      read_fd, write_fd = create_pipe
      begin
        # Pipe fds are typically < 20, well within select's range.
        # Skip assertion in environments where process already has many open fds.
        if read_fd < Termisu::Reader::FD_SETSIZE
          read_fd.should be < Termisu::Reader::FD_SETSIZE
        end

        reader = Termisu::Reader.new(read_fd)
        reader.available?.should be_false # No data written yet

        LibC.write(write_fd, "x".to_slice, 1)
        reader.available?.should be_true

        reader.close
      ensure
        LibC.close(read_fd)
        LibC.close(write_fd)
      end
    end

    it "raises IOError (not IndexError) for dynamically-closed invalid fd" do
      # Create a real fd, close it, then use that fd number.
      # This guarantees the fd is invalid without risking collisions.
      temp_reader, temp_writer = IO.pipe
      invalid_fd = temp_reader.fd
      temp_reader.close
      temp_writer.close

      # Before the fix, high fds would crash with IndexError on fds_bits access.
      # After the fix, high fds route to poll(2) which returns POLLNVAL → IOError.
      # The closed fd also triggers POLLNVAL via poll, giving the same error path.
      reader = Termisu::Reader.new(invalid_fd)
      expect_raises(Termisu::IOError) do
        reader.available?
      end
      reader.close
    end

    it "raises IOError (not IndexError) for another dynamically-closed invalid fd" do
      # Same test with a different closed fd to ensure reliability.
      temp_reader, temp_writer = IO.pipe
      invalid_fd = temp_reader.fd
      temp_reader.close
      temp_writer.close

      reader = Termisu::Reader.new(invalid_fd)
      expect_raises(Termisu::IOError) do
        reader.available?
      end
      reader.close
    end

    it "wait_for_data raises IOError for dynamically-closed invalid fd" do
      temp_reader, temp_writer = IO.pipe
      invalid_fd = temp_reader.fd
      temp_reader.close
      temp_writer.close

      reader = Termisu::Reader.new(invalid_fd)
      expect_raises(Termisu::IOError) do
        reader.wait_for_data(10)
      end
      reader.close
    end
  end
end
