require "../spec_helper"

describe Termisu::Termios do
  describe "#enable_raw_mode" do
    it "raises IO::Error with invalid file descriptor" do
      termios = Termisu::Termios.new(-1)

      expect_raises(IO::Error, /tcgetattr.*failed/) do
        termios.enable_raw_mode
      end
    end
  end

  describe "#restore" do
    it "is safe to call before enable_raw_mode and multiple times" do
      termios = Termisu::Termios.new(1)
      # No state saved, so restore is a no-op
      termios.restore
      termios.restore
      termios.restore

      # Even with invalid FD, restore is safe when no state saved
      termios_invalid = Termisu::Termios.new(-1)
      termios_invalid.restore
    end
  end

  describe "state management" do
    it "handles enable_raw_mode -> restore lifecycle on TTY" do
      termios = Termisu::Termios.new(STDOUT.fd)
      termios.enable_raw_mode
      termios.restore
    end
  end
end
