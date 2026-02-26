require "../../spec_helper"

describe Termisu::Terminal::Backend do
  describe "#read EINTR retry (BUG-005 regression)" do
    # Regression for issue #005: Backend#read had no EINTR retry loop, causing reads to fail
    # when interrupted by signals (e.g., SIGWINCH during input).
    # The fix wraps LibC.read in a loop that retries on EINTR.
    #
    # Direct EINTR injection requires signal timing which is non-deterministic.
    # These tests verify the happy path using Reader (which shares the same
    # EINTR retry pattern as Backend#read) with pipe file descriptors.

    it "Reader EINTR retry works with pipe (exercises same pattern as Backend#read)" do
      # Reader#fill_buffer uses the same EINTR retry pattern as Backend#read.
      # Test with a pipe to verify the retry loop's happy path returns data.
      read_fd, write_fd = create_pipe
      begin
        LibC.write(write_fd, "test".to_slice, 4)

        reader = Termisu::Reader.new(read_fd)
        byte = reader.read_byte
        byte.should_not be_nil
        byte.should eq('t'.ord.to_u8)

        reader.close
      ensure
        LibC.close(read_fd)
        LibC.close(write_fd)
      end
    end

    it "Reader EINTR retry handles EOF correctly" do
      read_fd, write_fd = create_pipe
      begin
        LibC.close(write_fd)
        write_fd = -1

        reader = Termisu::Reader.new(read_fd)
        # EOF should return nil, not raise (EINTR loop terminates on bytes_read == 0)
        byte = reader.read_byte
        byte.should be_nil

        reader.close
      ensure
        LibC.close(read_fd) if read_fd >= 0
        LibC.close(write_fd) if write_fd >= 0
      end
    end

    it "Reader has EINTR retry limit constant" do
      # Verify the retry limit exists (prevents infinite loop on signal storms)
      Termisu::Reader::MAX_EINTR_RETRIES.should be > 0
      Termisu::Reader::MAX_EINTR_RETRIES.should eq(100)
    end

    it "reads multiple bytes through EINTR-safe fill_buffer" do
      read_fd, write_fd = create_pipe
      begin
        LibC.write(write_fd, "abcdef".to_slice, 6)

        reader = Termisu::Reader.new(read_fd)
        bytes = reader.read_bytes(4)
        bytes.should_not be_nil
        if bytes
          String.new(bytes).should eq("abcd")
        end

        reader.close
      ensure
        LibC.close(read_fd)
        LibC.close(write_fd)
      end
    end

    it "peek_byte works through EINTR-safe fill_buffer" do
      read_fd, write_fd = create_pipe
      begin
        LibC.write(write_fd, "z".to_slice, 1)

        reader = Termisu::Reader.new(read_fd)
        # peek should return the byte without consuming it
        peeked = reader.peek_byte
        peeked.should eq('z'.ord.to_u8)

        # read should return the same byte
        byte = reader.read_byte
        byte.should eq('z'.ord.to_u8)

        reader.close
      ensure
        LibC.close(read_fd)
        LibC.close(write_fd)
      end
    end
  end
end
