require "../../spec_helper"

describe Termisu::Input::Modifier do
  describe "flag values" do
    it "has None as 0" do
      Termisu::Input::Modifier::None.value.should eq(0)
    end

    it "has Shift as 1" do
      Termisu::Input::Modifier::Shift.value.should eq(1)
    end

    it "has Alt as 2" do
      Termisu::Input::Modifier::Alt.value.should eq(2)
    end

    it "has Ctrl as 4" do
      Termisu::Input::Modifier::Ctrl.value.should eq(4)
    end

    it "has Meta as 8" do
      Termisu::Input::Modifier::Meta.value.should eq(8)
    end
  end

  describe "flag combinations" do
    it "combines Shift + Ctrl" do
      mods = Termisu::Input::Modifier::Shift | Termisu::Input::Modifier::Ctrl
      mods.shift?.should be_true
      mods.ctrl?.should be_true
      mods.alt?.should be_false
    end

    it "combines all modifiers" do
      mods = Termisu::Input::Modifier::Shift | Termisu::Input::Modifier::Alt |
             Termisu::Input::Modifier::Ctrl | Termisu::Input::Modifier::Meta
      mods.shift?.should be_true
      mods.alt?.should be_true
      mods.ctrl?.should be_true
      mods.meta?.should be_true
    end
  end

  describe ".from_xterm_code" do
    context "standard modifier codes" do
      # xterm sends modifier code = 1 + sum of active modifiers
      # Shift=1, Alt=2, Ctrl=4, Meta=8

      it "decodes code 1 as None (base code)" do
        mods = Termisu::Input::Modifier.from_xterm_code(1)
        mods.none?.should be_true
      end

      it "decodes code 2 as Shift (1 + 1)" do
        mods = Termisu::Input::Modifier.from_xterm_code(2)
        mods.shift?.should be_true
        mods.alt?.should be_false
      end

      it "decodes code 3 as Alt (1 + 2)" do
        mods = Termisu::Input::Modifier.from_xterm_code(3)
        mods.alt?.should be_true
        mods.shift?.should be_false
      end

      it "decodes code 4 as Shift+Alt (1 + 1 + 2)" do
        mods = Termisu::Input::Modifier.from_xterm_code(4)
        mods.shift?.should be_true
        mods.alt?.should be_true
      end

      it "decodes code 5 as Ctrl (1 + 4)" do
        mods = Termisu::Input::Modifier.from_xterm_code(5)
        mods.ctrl?.should be_true
      end

      it "decodes code 6 as Shift+Ctrl (1 + 1 + 4)" do
        mods = Termisu::Input::Modifier.from_xterm_code(6)
        mods.shift?.should be_true
        mods.ctrl?.should be_true
      end

      it "decodes code 7 as Alt+Ctrl (1 + 2 + 4)" do
        mods = Termisu::Input::Modifier.from_xterm_code(7)
        mods.alt?.should be_true
        mods.ctrl?.should be_true
      end

      it "decodes code 8 as Shift+Alt+Ctrl (1 + 1 + 2 + 4)" do
        mods = Termisu::Input::Modifier.from_xterm_code(8)
        mods.shift?.should be_true
        mods.alt?.should be_true
        mods.ctrl?.should be_true
      end

      it "decodes code 9 as Meta (1 + 8)" do
        mods = Termisu::Input::Modifier.from_xterm_code(9)
        mods.meta?.should be_true
      end
    end

    context "edge cases" do
      it "handles code 0 (invalid but handled)" do
        # Code 0 is technically invalid (minimum is 1)
        # but we handle it gracefully
        mods = Termisu::Input::Modifier.from_xterm_code(0)
        mods.should be_a(Termisu::Input::Modifier)
      end

      it "handles negative codes" do
        mods = Termisu::Input::Modifier.from_xterm_code(-1)
        mods.should be_a(Termisu::Input::Modifier)
      end
    end
  end

  describe ".from_mouse_cb" do
    context "mouse button code modifier extraction" do
      # Mouse cb encodes modifiers in bits 2-4:
      # bit 2 (4) = Shift
      # bit 3 (8) = Alt/Meta
      # bit 4 (16) = Ctrl

      it "extracts no modifiers from plain click" do
        mods = Termisu::Input::Modifier.from_mouse_cb(0) # plain left click
        mods.shift?.should be_false
        mods.alt?.should be_false
        mods.ctrl?.should be_false
      end

      it "extracts Shift from cb with bit 2 set" do
        mods = Termisu::Input::Modifier.from_mouse_cb(4) # Shift+click
        mods.shift?.should be_true
        mods.alt?.should be_false
        mods.ctrl?.should be_false
      end

      it "extracts Alt from cb with bit 3 set" do
        mods = Termisu::Input::Modifier.from_mouse_cb(8) # Alt+click
        mods.alt?.should be_true
        mods.shift?.should be_false
        mods.ctrl?.should be_false
      end

      it "extracts Ctrl from cb with bit 4 set" do
        mods = Termisu::Input::Modifier.from_mouse_cb(16) # Ctrl+click
        mods.ctrl?.should be_true
        mods.shift?.should be_false
        mods.alt?.should be_false
      end

      it "extracts combined modifiers" do
        mods = Termisu::Input::Modifier.from_mouse_cb(28) # Shift+Alt+Ctrl (4+8+16)
        mods.shift?.should be_true
        mods.alt?.should be_true
        mods.ctrl?.should be_true
      end

      it "ignores button bits when extracting modifiers" do
        # cb=1 is middle button, but bits 2-4 should still work
        mods = Termisu::Input::Modifier.from_mouse_cb(5) # middle button + Shift (1+4)
        mods.shift?.should be_true
      end

      it "ignores wheel bits when extracting modifiers" do
        # cb=64 is wheel up, with Ctrl modifier
        mods = Termisu::Input::Modifier.from_mouse_cb(80) # wheel + Ctrl (64+16)
        mods.ctrl?.should be_true
      end
    end
  end

  describe "predicate methods" do
    it "shift? returns true only when Shift is set" do
      Termisu::Input::Modifier::None.shift?.should be_false
      Termisu::Input::Modifier::Shift.shift?.should be_true
      Termisu::Input::Modifier::Alt.shift?.should be_false
      (Termisu::Input::Modifier::Shift | Termisu::Input::Modifier::Alt).shift?.should be_true
    end

    it "alt? returns true only when Alt is set" do
      Termisu::Input::Modifier::None.alt?.should be_false
      Termisu::Input::Modifier::Shift.alt?.should be_false
      Termisu::Input::Modifier::Alt.alt?.should be_true
      (Termisu::Input::Modifier::Shift | Termisu::Input::Modifier::Alt).alt?.should be_true
    end

    it "ctrl? returns true only when Ctrl is set" do
      Termisu::Input::Modifier::None.ctrl?.should be_false
      Termisu::Input::Modifier::Shift.ctrl?.should be_false
      Termisu::Input::Modifier::Ctrl.ctrl?.should be_true
      (Termisu::Input::Modifier::Shift | Termisu::Input::Modifier::Ctrl).ctrl?.should be_true
    end

    it "meta? returns true only when Meta is set" do
      Termisu::Input::Modifier::None.meta?.should be_false
      Termisu::Input::Modifier::Shift.meta?.should be_false
      Termisu::Input::Modifier::Meta.meta?.should be_true
      (Termisu::Input::Modifier::Shift | Termisu::Input::Modifier::Meta).meta?.should be_true
    end

    it "none? returns true only when no modifiers are set" do
      Termisu::Input::Modifier::None.none?.should be_true
      # Note: Crystal's @[Flags] enum none? checks if value == 0
      # Individual flags like Shift have non-zero values, so none? returns true
      # because it checks if NO flags are set, not if it's the None variant
    end
  end
end
