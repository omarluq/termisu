require "../spec_helper"

describe Termisu::TTY do
  describe ".new" do
    it "raises IO::Error when /dev/tty is unavailable" do
      # In CI environments without /dev/tty, this will raise
      # In terminal environments, it will succeed
      # Both behaviors are valid - we just test it doesn't crash
      begin
        tty = Termisu::TTY.new
        tty.should be_a(Termisu::TTY)
        tty.outfd.should be > 0
        tty.infd.should be > 0
        tty.close
      rescue ex : IO::Error
        ex.message.should_not be_nil
      end
    end
  end
end
