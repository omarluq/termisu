require "../../spec_helper"

describe Termisu::Event::Key do
  describe ".new" do
    it "creates a key event with default modifiers" do
      event = Termisu::Event::Key.new(Termisu::Input::Key::LowerA)
      event.key.should eq(Termisu::Input::Key::LowerA)
      event.modifiers.none?.should be_true
    end

    it "creates a key event with specified modifiers" do
      event = Termisu::Event::Key.new(Termisu::Input::Key::LowerA, Termisu::Input::Modifier::Ctrl)
      event.key.should eq(Termisu::Input::Key::LowerA)
      event.modifiers.ctrl?.should be_true
    end

    it "creates a key event with combined modifiers" do
      mods = Termisu::Input::Modifier::Ctrl | Termisu::Input::Modifier::Shift
      event = Termisu::Event::Key.new(Termisu::Input::Key::LowerA, mods)
      event.modifiers.ctrl?.should be_true
      event.modifiers.shift?.should be_true
    end
  end

  describe "#ctrl?" do
    it "returns true when Ctrl modifier is set" do
      event = Termisu::Event::Key.new(Termisu::Input::Key::LowerA, Termisu::Input::Modifier::Ctrl)
      event.ctrl?.should be_true
    end

    it "returns false when Ctrl modifier is not set" do
      event = Termisu::Event::Key.new(Termisu::Input::Key::LowerA, Termisu::Input::Modifier::Shift)
      event.ctrl?.should be_false
    end
  end

  describe "#alt?" do
    it "returns true when Alt modifier is set" do
      event = Termisu::Event::Key.new(Termisu::Input::Key::LowerA, Termisu::Input::Modifier::Alt)
      event.alt?.should be_true
    end

    it "returns false when Alt modifier is not set" do
      event = Termisu::Event::Key.new(Termisu::Input::Key::LowerA)
      event.alt?.should be_false
    end
  end

  describe "#shift?" do
    it "returns true when Shift modifier is set" do
      event = Termisu::Event::Key.new(Termisu::Input::Key::LowerA, Termisu::Input::Modifier::Shift)
      event.shift?.should be_true
    end

    it "returns false when Shift modifier is not set" do
      event = Termisu::Event::Key.new(Termisu::Input::Key::LowerA)
      event.shift?.should be_false
    end
  end

  describe "#meta?" do
    it "returns true when Meta modifier is set" do
      event = Termisu::Event::Key.new(Termisu::Input::Key::LowerA, Termisu::Input::Modifier::Meta)
      event.meta?.should be_true
    end

    it "returns false when Meta modifier is not set" do
      event = Termisu::Event::Key.new(Termisu::Input::Key::LowerA)
      event.meta?.should be_false
    end
  end

  describe "#ctrl_c?" do
    it "returns true for Ctrl+C" do
      event = Termisu::Event::Key.new(Termisu::Input::Key::LowerC, Termisu::Input::Modifier::Ctrl)
      event.ctrl_c?.should be_true
    end

    it "returns false for Ctrl+UpperC (implementation checks lowercase only)" do
      # The implementation checks for lower_c? specifically
      # Ctrl+C from terminal sends 0x03 which maps to lowercase c
      event = Termisu::Event::Key.new(Termisu::Input::Key::UpperC, Termisu::Input::Modifier::Ctrl)
      event.ctrl_c?.should be_false
    end

    it "returns false for just 'c'" do
      event = Termisu::Event::Key.new(Termisu::Input::Key::LowerC)
      event.ctrl_c?.should be_false
    end

    it "returns false for Ctrl+other key" do
      event = Termisu::Event::Key.new(Termisu::Input::Key::LowerA, Termisu::Input::Modifier::Ctrl)
      event.ctrl_c?.should be_false
    end
  end

  describe "#ctrl_d?" do
    it "returns true for Ctrl+D" do
      event = Termisu::Event::Key.new(Termisu::Input::Key::LowerD, Termisu::Input::Modifier::Ctrl)
      event.ctrl_d?.should be_true
    end

    it "returns false for just 'd'" do
      event = Termisu::Event::Key.new(Termisu::Input::Key::LowerD)
      event.ctrl_d?.should be_false
    end
  end

  describe "#ctrl_z?" do
    it "returns true for Ctrl+Z" do
      event = Termisu::Event::Key.new(Termisu::Input::Key::LowerZ, Termisu::Input::Modifier::Ctrl)
      event.ctrl_z?.should be_true
    end

    it "returns false for just 'z'" do
      event = Termisu::Event::Key.new(Termisu::Input::Key::LowerZ)
      event.ctrl_z?.should be_false
    end
  end

  describe "#ctrl_q?" do
    it "returns true for Ctrl+Q" do
      event = Termisu::Event::Key.new(Termisu::Input::Key::LowerQ, Termisu::Input::Modifier::Ctrl)
      event.ctrl_q?.should be_true
    end

    it "returns false for just 'q'" do
      event = Termisu::Event::Key.new(Termisu::Input::Key::LowerQ)
      event.ctrl_q?.should be_false
    end
  end

  describe "#char" do
    it "returns character for printable keys" do
      event = Termisu::Event::Key.new(Termisu::Input::Key::LowerA)
      event.char.should eq('a')
    end

    it "returns nil for non-printable keys" do
      event = Termisu::Event::Key.new(Termisu::Input::Key::Up)
      event.char.should be_nil
    end

    it "returns nil for function keys" do
      event = Termisu::Event::Key.new(Termisu::Input::Key::F1)
      event.char.should be_nil
    end

    it "returns space character for Space key" do
      event = Termisu::Event::Key.new(Termisu::Input::Key::Space)
      event.char.should eq(' ')
    end
  end

  describe "special keys" do
    it "handles Escape key" do
      event = Termisu::Event::Key.new(Termisu::Input::Key::Escape)
      event.key.escape?.should be_true
    end

    it "handles Enter key" do
      event = Termisu::Event::Key.new(Termisu::Input::Key::Enter)
      event.key.enter?.should be_true
      event.char.should eq('\n')
    end

    it "handles Backspace key" do
      event = Termisu::Event::Key.new(Termisu::Input::Key::Backspace)
      event.key.backspace?.should be_true
    end

    it "handles Tab key" do
      event = Termisu::Event::Key.new(Termisu::Input::Key::Tab)
      event.key.tab?.should be_true
      event.char.should eq('\t')
    end

    it "handles BackTab (Shift+Tab)" do
      event = Termisu::Event::Key.new(Termisu::Input::Key::BackTab)
      event.key.back_tab?.should be_true
    end
  end

  describe "arrow keys" do
    it "handles Up arrow" do
      event = Termisu::Event::Key.new(Termisu::Input::Key::Up)
      event.key.up?.should be_true
      event.key.navigation?.should be_true
    end

    it "handles Down arrow" do
      event = Termisu::Event::Key.new(Termisu::Input::Key::Down)
      event.key.down?.should be_true
    end

    it "handles Left arrow" do
      event = Termisu::Event::Key.new(Termisu::Input::Key::Left)
      event.key.left?.should be_true
    end

    it "handles Right arrow" do
      event = Termisu::Event::Key.new(Termisu::Input::Key::Right)
      event.key.right?.should be_true
    end

    it "handles arrow keys with Shift modifier" do
      event = Termisu::Event::Key.new(Termisu::Input::Key::Up, Termisu::Input::Modifier::Shift)
      event.key.up?.should be_true
      event.shift?.should be_true
    end
  end

  describe "function keys" do
    it "handles F1" do
      event = Termisu::Event::Key.new(Termisu::Input::Key::F1)
      event.key.f1?.should be_true
      event.key.function_key?.should be_true
    end

    it "handles F12" do
      event = Termisu::Event::Key.new(Termisu::Input::Key::F12)
      event.key.f12?.should be_true
    end

    it "handles function keys with modifiers" do
      mods = Termisu::Input::Modifier::Ctrl | Termisu::Input::Modifier::Shift
      event = Termisu::Event::Key.new(Termisu::Input::Key::F5, mods)
      event.key.f5?.should be_true
      event.ctrl?.should be_true
      event.shift?.should be_true
    end
  end
end
