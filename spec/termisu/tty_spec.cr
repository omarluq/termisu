require "../spec_helper"

describe Termisu::TTY do
  describe ".new" do
    it "opens /dev/tty successfully" do
      tty = Termisu::TTY.new
      tty.should be_a(Termisu::TTY)
    ensure
      tty.try &.close
    end

    it "provides valid file descriptors" do
      tty = Termisu::TTY.new
      tty.outfd.should be >= 0
      tty.infd.should be >= 0
    ensure
      tty.try &.close
    end
  end

  describe "#write" do
    it "writes data to the terminal" do
      tty = Termisu::TTY.new
      # Should not raise
      tty.write("test")
    ensure
      tty.try &.close
    end

    it "writes escape sequences" do
      tty = Termisu::TTY.new
      # Should not raise
      tty.write("\e[2J")
    ensure
      tty.try &.close
    end
  end

  describe "#flush" do
    it "flushes the output buffer" do
      tty = Termisu::TTY.new
      tty.write("test")
      # Should not raise
      tty.flush
    ensure
      tty.try &.close
    end
  end

  describe "#close" do
    it "closes without error" do
      tty = Termisu::TTY.new
      # Should not raise
      tty.close
    end

    it "can be called multiple times safely" do
      tty = Termisu::TTY.new
      tty.close
      # Second close should not raise
      tty.close
    end
  end

  describe "file descriptor accessors" do
    it "returns consistent outfd" do
      tty = Termisu::TTY.new
      fd1 = tty.outfd
      fd2 = tty.outfd
      fd1.should eq(fd2)
    ensure
      tty.try &.close
    end

    it "returns consistent infd" do
      tty = Termisu::TTY.new
      fd1 = tty.infd
      fd2 = tty.infd
      fd1.should eq(fd2)
    ensure
      tty.try &.close
    end
  end
end
