require "../../spec_helper"

describe Termisu::Terminal::Mode do
  describe "enum values" do
    it "has None flag" do
      Termisu::Terminal::Mode::None.value.should eq(0)
    end

    it "has Canonical flag" do
      Termisu::Terminal::Mode::Canonical.value.should eq(1)
    end

    it "has Echo flag" do
      Termisu::Terminal::Mode::Echo.value.should eq(2)
    end

    it "has Signals flag" do
      Termisu::Terminal::Mode::Signals.value.should eq(4)
    end

    it "has Extended flag" do
      Termisu::Terminal::Mode::Extended.value.should eq(8)
    end
  end

  describe "preset methods" do
    describe ".raw" do
      it "returns None (no flags set)" do
        mode = Termisu::Terminal::Mode.raw
        mode.should eq(Termisu::Terminal::Mode::None)
        mode.none?.should be_true
      end

      it "has no flags enabled" do
        mode = Termisu::Terminal::Mode.raw
        mode.canonical?.should be_false
        mode.echo?.should be_false
        mode.signals?.should be_false
        mode.extended?.should be_false
      end
    end

    describe ".cooked" do
      it "returns Canonical | Echo | Signals | Extended" do
        mode = Termisu::Terminal::Mode.cooked
        expected = Termisu::Terminal::Mode::Canonical |
                   Termisu::Terminal::Mode::Echo |
                   Termisu::Terminal::Mode::Signals |
                   Termisu::Terminal::Mode::Extended
        mode.should eq(expected)
      end

      it "has all flags enabled" do
        mode = Termisu::Terminal::Mode.cooked
        mode.canonical?.should be_true
        mode.echo?.should be_true
        mode.signals?.should be_true
        mode.extended?.should be_true
      end
    end

    describe ".cbreak" do
      it "returns Echo | Signals" do
        mode = Termisu::Terminal::Mode.cbreak
        expected = Termisu::Terminal::Mode::Echo |
                   Termisu::Terminal::Mode::Signals
        mode.should eq(expected)
      end

      it "has echo and signals but not canonical" do
        mode = Termisu::Terminal::Mode.cbreak
        mode.canonical?.should be_false
        mode.echo?.should be_true
        mode.signals?.should be_true
        mode.extended?.should be_false
      end
    end

    describe ".password" do
      it "returns Canonical | Signals" do
        mode = Termisu::Terminal::Mode.password
        expected = Termisu::Terminal::Mode::Canonical |
                   Termisu::Terminal::Mode::Signals
        mode.should eq(expected)
      end

      it "has canonical and signals but no echo" do
        mode = Termisu::Terminal::Mode.password
        mode.canonical?.should be_true
        mode.echo?.should be_false
        mode.signals?.should be_true
        mode.extended?.should be_false
      end
    end

    describe ".semi_raw" do
      it "returns Signals only" do
        mode = Termisu::Terminal::Mode.semi_raw
        mode.should eq(Termisu::Terminal::Mode::Signals)
      end

      it "has only signals enabled" do
        mode = Termisu::Terminal::Mode.semi_raw
        mode.canonical?.should be_false
        mode.echo?.should be_false
        mode.signals?.should be_true
        mode.extended?.should be_false
      end
    end
  end

  describe "flag combinations" do
    it "can combine Canonical and Echo" do
      mode = Termisu::Terminal::Mode::Canonical | Termisu::Terminal::Mode::Echo
      mode.canonical?.should be_true
      mode.echo?.should be_true
      mode.signals?.should be_false
      mode.extended?.should be_false
    end

    it "can combine all flags" do
      mode = Termisu::Terminal::Mode::Canonical |
             Termisu::Terminal::Mode::Echo |
             Termisu::Terminal::Mode::Signals |
             Termisu::Terminal::Mode::Extended
      mode.canonical?.should be_true
      mode.echo?.should be_true
      mode.signals?.should be_true
      mode.extended?.should be_true
    end

    it "can check for None" do
      mode = Termisu::Terminal::Mode::None
      mode.none?.should be_true
      mode.canonical?.should be_false
      mode.echo?.should be_false
      mode.signals?.should be_false
      mode.extended?.should be_false
    end

    it "supports bitwise operations" do
      mode = Termisu::Terminal::Mode::Canonical | Termisu::Terminal::Mode::Echo
      mode.value.should eq(3) # 1 | 2 = 3
    end
  end

  describe "mode comparisons" do
    it "raw equals None" do
      Termisu::Terminal::Mode.raw.should eq(Termisu::Terminal::Mode::None)
    end

    it "different presets are not equal" do
      Termisu::Terminal::Mode.raw.should_not eq(Termisu::Terminal::Mode.cooked)
      Termisu::Terminal::Mode.cbreak.should_not eq(Termisu::Terminal::Mode.password)
    end

    it "custom combination equals equivalent preset" do
      custom = Termisu::Terminal::Mode::Canonical |
               Termisu::Terminal::Mode::Echo |
               Termisu::Terminal::Mode::Signals |
               Termisu::Terminal::Mode::Extended
      custom.should eq(Termisu::Terminal::Mode.cooked)
    end
  end
end
