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
  end
end
