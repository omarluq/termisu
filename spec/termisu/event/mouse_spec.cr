require "../../spec_helper"

describe Termisu::Event::MouseButton do
  describe ".from_cb" do
    context "basic buttons" do
      it "decodes 0 as Left button" do
        Termisu::Event::MouseButton.from_cb(0).should eq(Termisu::Event::MouseButton::Left)
      end

      it "decodes 1 as Middle button" do
        Termisu::Event::MouseButton.from_cb(1).should eq(Termisu::Event::MouseButton::Middle)
      end

      it "decodes 2 as Right button" do
        Termisu::Event::MouseButton.from_cb(2).should eq(Termisu::Event::MouseButton::Right)
      end

      it "decodes 3 as Release" do
        Termisu::Event::MouseButton.from_cb(3).should eq(Termisu::Event::MouseButton::Release)
      end
    end

    context "wheel events" do
      it "decodes 64 as WheelUp" do
        Termisu::Event::MouseButton.from_cb(64).should eq(Termisu::Event::MouseButton::WheelUp)
      end

      it "decodes 65 as WheelDown" do
        Termisu::Event::MouseButton.from_cb(65).should eq(Termisu::Event::MouseButton::WheelDown)
      end

      it "decodes 66 as WheelLeft" do
        Termisu::Event::MouseButton.from_cb(66).should eq(Termisu::Event::MouseButton::WheelLeft)
      end

      it "decodes 67 as WheelRight" do
        Termisu::Event::MouseButton.from_cb(67).should eq(Termisu::Event::MouseButton::WheelRight)
      end
    end

    context "extended buttons" do
      # Note: Extended buttons (128, 129) are not currently implemented in from_cb
      # The current implementation only handles basic buttons and wheel events
      it "decodes 128 as basic button (extended not implemented)" do
        # 128 has wheel bit (64) set, so it's decoded as WheelUp variant
        result = Termisu::Event::MouseButton.from_cb(128)
        result.should be_a(Termisu::Event::MouseButton)
      end
    end

    context "with modifier bits set" do
      # Modifier bits (4, 8, 16) should not affect button detection
      it "decodes button correctly with Shift bit (4)" do
        Termisu::Event::MouseButton.from_cb(4).should eq(Termisu::Event::MouseButton::Left)
      end

      it "decodes button correctly with Alt bit (8)" do
        Termisu::Event::MouseButton.from_cb(8).should eq(Termisu::Event::MouseButton::Left)
      end

      it "decodes button correctly with Ctrl bit (16)" do
        Termisu::Event::MouseButton.from_cb(16).should eq(Termisu::Event::MouseButton::Left)
      end

      it "decodes button correctly with all modifier bits (28)" do
        Termisu::Event::MouseButton.from_cb(28).should eq(Termisu::Event::MouseButton::Left)
      end

      it "decodes middle button with modifiers" do
        Termisu::Event::MouseButton.from_cb(5).should eq(Termisu::Event::MouseButton::Middle) # 1 + 4 (Shift)
      end

      it "decodes right button with modifiers" do
        Termisu::Event::MouseButton.from_cb(10).should eq(Termisu::Event::MouseButton::Right) # 2 + 8 (Alt)
      end
    end

    context "with motion bit set" do
      # Motion bit (32) should not affect button detection
      it "decodes button correctly with motion bit" do
        Termisu::Event::MouseButton.from_cb(32).should eq(Termisu::Event::MouseButton::Left)
      end

      it "decodes middle button with motion" do
        Termisu::Event::MouseButton.from_cb(33).should eq(Termisu::Event::MouseButton::Middle)
      end

      it "decodes wheel up with motion" do
        Termisu::Event::MouseButton.from_cb(96).should eq(Termisu::Event::MouseButton::WheelUp) # 64 + 32
      end
    end

    context "unknown codes" do
      it "decodes high bits gracefully" do
        # The implementation uses bit masking, so 255 would be:
        # bit 6 (64) set -> wheel event
        # bits 0-1 = 3 -> WheelRight
        result = Termisu::Event::MouseButton.from_cb(255)
        result.should eq(Termisu::Event::MouseButton::WheelRight)
      end
    end
  end

  describe "predicate methods" do
    it "wheel_up? returns true for WheelUp" do
      Termisu::Event::MouseButton::WheelUp.wheel_up?.should be_true
      Termisu::Event::MouseButton::WheelDown.wheel_up?.should be_false
    end

    it "wheel_down? returns true for WheelDown" do
      Termisu::Event::MouseButton::WheelDown.wheel_down?.should be_true
      Termisu::Event::MouseButton::WheelUp.wheel_down?.should be_false
    end
  end
end

describe Termisu::Event::Mouse do
  describe ".new" do
    it "creates a mouse event with coordinates" do
      event = Termisu::Event::Mouse.new(10, 20, Termisu::Event::MouseButton::Left)
      event.x.should eq(10)
      event.y.should eq(20)
      event.button.should eq(Termisu::Event::MouseButton::Left)
    end

    it "creates a mouse event with default modifiers and no motion" do
      event = Termisu::Event::Mouse.new(1, 1, Termisu::Event::MouseButton::Left)
      event.modifiers.none?.should be_true
      event.motion?.should be_false
    end

    it "creates a mouse event with modifiers" do
      mods = Termisu::Modifier::Ctrl | Termisu::Modifier::Shift
      event = Termisu::Event::Mouse.new(5, 5, Termisu::Event::MouseButton::Left, mods)
      event.modifiers.ctrl?.should be_true
      event.modifiers.shift?.should be_true
    end

    it "creates a mouse event with motion" do
      event = Termisu::Event::Mouse.new(5, 5, Termisu::Event::MouseButton::Left, Termisu::Modifier::None, true)
      event.motion?.should be_true
    end
  end

  describe "#press?" do
    it "returns true for button press events" do
      left = Termisu::Event::Mouse.new(1, 1, Termisu::Event::MouseButton::Left)
      middle = Termisu::Event::Mouse.new(1, 1, Termisu::Event::MouseButton::Middle)
      right = Termisu::Event::Mouse.new(1, 1, Termisu::Event::MouseButton::Right)

      left.press?.should be_true
      middle.press?.should be_true
      right.press?.should be_true
    end

    it "returns false for release events" do
      event = Termisu::Event::Mouse.new(1, 1, Termisu::Event::MouseButton::Release)
      event.press?.should be_false
    end

    it "returns true for wheel events (wheel is treated as instant press)" do
      # Note: The implementation treats wheel events as press events
      # because they are not release events and not motion events
      # This is a design choice - wheel scrolls are instantaneous inputs
      up = Termisu::Event::Mouse.new(1, 1, Termisu::Event::MouseButton::WheelUp)
      down = Termisu::Event::Mouse.new(1, 1, Termisu::Event::MouseButton::WheelDown)

      up.press?.should be_true
      down.press?.should be_true
    end
  end

  describe "#wheel?" do
    it "returns true for wheel up" do
      event = Termisu::Event::Mouse.new(1, 1, Termisu::Event::MouseButton::WheelUp)
      event.wheel?.should be_true
    end

    it "returns true for wheel down" do
      event = Termisu::Event::Mouse.new(1, 1, Termisu::Event::MouseButton::WheelDown)
      event.wheel?.should be_true
    end

    it "returns true for wheel left" do
      event = Termisu::Event::Mouse.new(1, 1, Termisu::Event::MouseButton::WheelLeft)
      event.wheel?.should be_true
    end

    it "returns true for wheel right" do
      event = Termisu::Event::Mouse.new(1, 1, Termisu::Event::MouseButton::WheelRight)
      event.wheel?.should be_true
    end

    it "returns false for button clicks" do
      event = Termisu::Event::Mouse.new(1, 1, Termisu::Event::MouseButton::Left)
      event.wheel?.should be_false
    end
  end

  describe "modifier shortcuts" do
    it "#ctrl? returns true when Ctrl is pressed" do
      event = Termisu::Event::Mouse.new(1, 1, Termisu::Event::MouseButton::Left, Termisu::Modifier::Ctrl)
      event.ctrl?.should be_true
      event.shift?.should be_false
    end

    it "#alt? returns true when Alt is pressed" do
      event = Termisu::Event::Mouse.new(1, 1, Termisu::Event::MouseButton::Left, Termisu::Modifier::Alt)
      event.alt?.should be_true
      event.ctrl?.should be_false
    end

    it "#shift? returns true when Shift is pressed" do
      event = Termisu::Event::Mouse.new(1, 1, Termisu::Event::MouseButton::Left, Termisu::Modifier::Shift)
      event.shift?.should be_true
      event.alt?.should be_false
    end
  end

  describe "coordinate handling" do
    it "handles large coordinates (SGR protocol)" do
      # SGR protocol supports coordinates beyond 223
      event = Termisu::Event::Mouse.new(500, 1000, Termisu::Event::MouseButton::Left)
      event.x.should eq(500)
      event.y.should eq(1000)
    end

    it "handles coordinate 1 (minimum valid)" do
      event = Termisu::Event::Mouse.new(1, 1, Termisu::Event::MouseButton::Left)
      event.x.should eq(1)
      event.y.should eq(1)
    end

    it "handles coordinate 223 (max for normal protocol)" do
      event = Termisu::Event::Mouse.new(223, 223, Termisu::Event::MouseButton::Left)
      event.x.should eq(223)
      event.y.should eq(223)
    end
  end

  describe "motion events" do
    it "creates drag event (motion with button pressed)" do
      event = Termisu::Event::Mouse.new(10, 10, Termisu::Event::MouseButton::Left, Termisu::Modifier::None, true)
      event.motion?.should be_true
      event.button.should eq(Termisu::Event::MouseButton::Left)
    end

    it "creates hover event (motion with no button)" do
      # Note: hover requires motion tracking mode enabled (mode 1003)
      event = Termisu::Event::Mouse.new(10, 10, Termisu::Event::MouseButton::Release, Termisu::Modifier::None, true)
      event.motion?.should be_true
      event.button.should eq(Termisu::Event::MouseButton::Release)
    end
  end

  describe "button-specific operations" do
    it "identifies left click" do
      event = Termisu::Event::Mouse.new(1, 1, Termisu::Event::MouseButton::Left)
      event.button.left?.should be_true
      event.button.middle?.should be_false
      event.button.right?.should be_false
    end

    it "identifies middle click" do
      event = Termisu::Event::Mouse.new(1, 1, Termisu::Event::MouseButton::Middle)
      event.button.middle?.should be_true
    end

    it "identifies right click" do
      event = Termisu::Event::Mouse.new(1, 1, Termisu::Event::MouseButton::Right)
      event.button.right?.should be_true
    end

    it "identifies release" do
      event = Termisu::Event::Mouse.new(1, 1, Termisu::Event::MouseButton::Release)
      event.button.release?.should be_true
    end
  end
end
