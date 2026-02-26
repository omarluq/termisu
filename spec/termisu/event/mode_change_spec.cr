require "../../spec_helper"

describe Termisu::Event::ModeChange do
  describe ".new" do
    it "creates event with mode and previous_mode" do
      event = Termisu::Event::ModeChange.new(
        mode: Termisu::Terminal::Mode.raw,
        previous_mode: Termisu::Terminal::Mode.cooked,
      )

      event.mode.should eq(Termisu::Terminal::Mode.raw)
      event.previous_mode.should eq(Termisu::Terminal::Mode.cooked)
    end

    it "creates event with nil previous_mode by default" do
      event = Termisu::Event::ModeChange.new(mode: Termisu::Terminal::Mode.raw)

      event.mode.should eq(Termisu::Terminal::Mode.raw)
      event.previous_mode.should be_nil
    end
  end

  describe "#changed?" do
    it "returns false when previous_mode is nil (first assignment)" do
      event = Termisu::Event::ModeChange.new(mode: Termisu::Terminal::Mode.raw)

      event.changed?.should be_false
    end

    it "returns false when previous_mode equals current mode" do
      event = Termisu::Event::ModeChange.new(
        mode: Termisu::Terminal::Mode.raw,
        previous_mode: Termisu::Terminal::Mode.raw,
      )

      event.changed?.should be_false
    end

    it "returns true when mode differs from previous_mode" do
      event = Termisu::Event::ModeChange.new(
        mode: Termisu::Terminal::Mode.raw,
        previous_mode: Termisu::Terminal::Mode.cooked,
      )

      event.changed?.should be_true
    end

    it "returns true for raw to cooked transition" do
      event = Termisu::Event::ModeChange.new(
        mode: Termisu::Terminal::Mode.cooked,
        previous_mode: Termisu::Terminal::Mode.raw,
      )

      event.changed?.should be_true
    end

    it "returns false when same non-raw modes" do
      event = Termisu::Event::ModeChange.new(
        mode: Termisu::Terminal::Mode.cooked,
        previous_mode: Termisu::Terminal::Mode.cooked,
      )

      event.changed?.should be_false
    end
  end

  describe "#changed? (BUG-004 regression)" do
    it "returns false for first change with nil previous_mode" do
      event = Termisu::Event::ModeChange.new(
        mode: Termisu::Terminal::Mode::Echo,
        previous_mode: nil,
      )

      event.changed?.should be_false
    end

    it "returns true when mode differs from previous_mode (Echo vs None)" do
      event = Termisu::Event::ModeChange.new(
        mode: Termisu::Terminal::Mode::Echo,
        previous_mode: Termisu::Terminal::Mode::None,
      )

      event.changed?.should be_true
    end

    it "returns false for same-mode transition (Echo to Echo)" do
      event = Termisu::Event::ModeChange.new(
        mode: Termisu::Terminal::Mode::Echo,
        previous_mode: Termisu::Terminal::Mode::Echo,
      )

      event.changed?.should be_false
    end
  end

  describe "#to_raw?" do
    it "returns true when transitioning to raw mode" do
      event = Termisu::Event::ModeChange.new(
        mode: Termisu::Terminal::Mode.raw,
        previous_mode: Termisu::Terminal::Mode.cooked,
      )

      event.to_raw?.should be_true
    end

    it "returns false when not transitioning to raw mode" do
      event = Termisu::Event::ModeChange.new(
        mode: Termisu::Terminal::Mode.cooked,
        previous_mode: Termisu::Terminal::Mode.cooked,
      )

      event.to_raw?.should be_false
    end
  end

  describe "#from_raw?" do
    it "returns true when transitioning from raw mode" do
      event = Termisu::Event::ModeChange.new(
        mode: Termisu::Terminal::Mode.cooked,
        previous_mode: Termisu::Terminal::Mode.raw,
      )

      event.from_raw?.should be_true
    end

    it "returns false when previous_mode is nil" do
      event = Termisu::Event::ModeChange.new(mode: Termisu::Terminal::Mode.raw)

      event.from_raw?.should be_false
    end

    it "returns false when not transitioning from raw mode" do
      event = Termisu::Event::ModeChange.new(
        mode: Termisu::Terminal::Mode.cooked,
        previous_mode: Termisu::Terminal::Mode.cooked,
      )

      event.from_raw?.should be_false
    end
  end

  describe "#to_user_interactive?" do
    it "returns true when transitioning to cooked mode" do
      event = Termisu::Event::ModeChange.new(
        mode: Termisu::Terminal::Mode.cooked,
        previous_mode: Termisu::Terminal::Mode.raw,
      )

      event.to_user_interactive?.should be_true
    end

    it "returns false when transitioning to raw mode" do
      event = Termisu::Event::ModeChange.new(
        mode: Termisu::Terminal::Mode.raw,
        previous_mode: Termisu::Terminal::Mode.cooked,
      )

      event.to_user_interactive?.should be_false
    end
  end

  describe "#from_user_interactive?" do
    it "returns true when transitioning from cooked mode" do
      event = Termisu::Event::ModeChange.new(
        mode: Termisu::Terminal::Mode.raw,
        previous_mode: Termisu::Terminal::Mode.cooked,
      )

      event.from_user_interactive?.should be_true
    end

    it "returns false when previous_mode is nil" do
      event = Termisu::Event::ModeChange.new(mode: Termisu::Terminal::Mode.cooked)

      event.from_user_interactive?.should be_false
    end

    it "returns false when transitioning from raw mode" do
      event = Termisu::Event::ModeChange.new(
        mode: Termisu::Terminal::Mode.cooked,
        previous_mode: Termisu::Terminal::Mode.raw,
      )

      event.from_user_interactive?.should be_false
    end
  end
end
