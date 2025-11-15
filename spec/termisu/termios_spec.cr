require "../spec_helper"

describe Termisu::Termios do
  describe "LibC constants" do
    it "has VMIN defined" do
      LibC::VMIN.should be_a(Int32)
    end

    it "has VTIME defined" do
      LibC::VTIME.should be_a(Int32)
    end
  end

  describe "#enable_raw_mode" do
    it "raises IO::Error with invalid file descriptor" do
      termios = Termisu::Termios.new(-1)
      expect_raises(IO::Error, /tcgetattr failed/) do
        termios.enable_raw_mode
      end
    end
  end
end
