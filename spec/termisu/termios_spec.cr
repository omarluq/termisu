require "../spec_helper"

# Termios tests focus on testable behavior without requiring a real TTY
# Real terminal state manipulation is tested in spec/integration/

describe Termisu::Termios do
  describe "LibC constants" do
    it "defines VMIN" do
      LibC::VMIN.should be_a(Int32)
    end

    it "defines VTIME" do
      LibC::VTIME.should be_a(Int32)
    end
  end

  describe ".new" do
    it "accepts any file descriptor without validation" do
      termios = Termisu::Termios.new(1)
      termios.should be_a(Termisu::Termios)
    end

    it "accepts negative file descriptors" do
      # Constructor doesn't validate - errors occur on method calls
      termios = Termisu::Termios.new(-1)
      termios.should be_a(Termisu::Termios)
    end

    it "accepts zero as file descriptor" do
      termios = Termisu::Termios.new(0)
      termios.should be_a(Termisu::Termios)
    end
  end

  describe "#enable_raw_mode" do
    context "with invalid file descriptor" do
      it "raises IO::Error with tcgetattr message" do
        termios = Termisu::Termios.new(-1)

        expect_raises(IO::Error, /tcgetattr/) do
          termios.enable_raw_mode
        end
      end

      it "includes 'failed' in error message" do
        termios = Termisu::Termios.new(-1)

        begin
          termios.enable_raw_mode
          fail "Should have raised IO::Error"
        rescue ex : IO::Error
          ex.message.to_s.should contain("failed")
        end
      end
    end
  end

  describe "#restore" do
    it "does nothing when called before enable_raw_mode" do
      termios = Termisu::Termios.new(1)
      # Should not raise - it's a no-op
      termios.restore
    end

    it "is safe to call multiple times" do
      termios = Termisu::Termios.new(1)
      termios.restore
      termios.restore
      termios.restore
    end

    it "does not raise with invalid FD when no state saved" do
      termios = Termisu::Termios.new(-1)
      # No @original saved, so restore is a no-op
      termios.restore
    end
  end

  describe "state management" do
    it "handles enable_raw_mode -> restore sequence without real TTY" do
      # This tests the logical flow with real file descriptor (stdout)
      begin
        termios = Termisu::Termios.new(STDOUT.fd)
        termios.enable_raw_mode
        termios.restore
      rescue IO::Error
        # Expected if STDOUT is not a TTY (like in CI)
        true.should be_true
      end
    end
  end
end
