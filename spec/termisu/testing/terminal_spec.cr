require "spec"
require "../../../src/termisu"
require "../../../src/termisu/testing"

describe Termisu::Testing::Terminal do
  describe "#wait_until" do
    it "returns true as soon as the condition holds" do
      Termisu::Testing.terminal("sh", ["-c", "printf ready; exec sleep 5"]) do |term|
        term.get_by_text("ready").should be_true

        elapsed = Time.measure do
          term.wait_until(1.second) { true }.should be_true
        end
        elapsed.should be < 100.milliseconds
      end
    end

    it "returns false once the timeout elapses without the condition" do
      Termisu::Testing.terminal("sh", ["-c", "exec sleep 5"]) do |term|
        elapsed = Time.measure do
          term.wait_until(120.milliseconds) { false }.should be_false
        end
        elapsed.should be >= 120.milliseconds
        elapsed.should be < 1.second
      end
    end
  end

  describe "#wait_stable" do
    it "returns true once output quiesces" do
      Termisu::Testing.terminal("sh", ["-c", "printf hello; exec sleep 5"]) do |term|
        term.wait_stable(quiet_for: 40.milliseconds).should be_true
      end
    end

    it "returns false at the deadline when output never quiesces" do
      # Writes every ~20ms so a 300ms quiet window is never reached.
      Termisu::Testing.terminal("sh", ["-c", "while :; do printf x; sleep 0.02; done"]) do |term|
        elapsed = Time.measure do
          term.wait_stable(quiet_for: 300.milliseconds, timeout: 700.milliseconds).should be_false
        end
        elapsed.should be >= 600.milliseconds
        elapsed.should be < 3.seconds
      end
    end
  end
end
