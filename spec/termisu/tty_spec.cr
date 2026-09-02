require "../spec_helper"

describe Termisu::TTY do
  describe ".new" do
    it "opens /dev/tty and provides valid file descriptors" do
      tty = Termisu::TTY.new
      tty.outfd.should be >= 0
      tty.infd.should be >= 0
    ensure
      tty.try &.close
    end
  end

  describe "#write and #flush" do
    it "writes escape sequences to the terminal" do
      tty = Termisu::TTY.new
      # Write cursor save and restore - harmless escape sequence
      tty.write("\e7") # Save cursor
      tty.flush
      tty.write("\e8") # Restore cursor
      tty.flush
    ensure
      tty.try &.close
    end
  end

  describe "#close" do
    it "can be called multiple times safely (idempotent)" do
      tty = Termisu::TTY.new
      tty.close
      tty.close # Should not raise
      tty.close # Should not raise
    end

    {% unless flag?(:openbsd) || flag?(:freebsd) %}
      it "does not close a descriptor that reuses its input descriptor number" do
        tty = Termisu::TTY.new
        input_fd = tty.infd
        tty.close

        reused_fds = [] of Int32
        begin
          loop do
            fd = LibC.open("/dev/null", LibC::O_RDONLY, 0)
            raise IO::Error.from_errno("Failed to open /dev/null") if fd == -1
            reused_fds << fd
            break if fd == input_fd
            raise "Could not reuse TTY input descriptor #{input_fd}" if fd > input_fd
          end

          tty.close
          LibC.fcntl(input_fd, LibC::F_GETFD, 0).should_not eq(-1)
        ensure
          tty.try &.close
          reused_fds.each { |fd| LibC.close(fd) }
        end
      end
    {% end %}
  end
end
