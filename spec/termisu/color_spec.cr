require "../spec_helper"

describe Termisu::Color do
  describe "Color modes" do
    it "supports ANSI-8 mode" do
      color = Termisu::Color.ansi8(3)
      color.mode.should eq(Termisu::Color::Mode::ANSI8)
      color.index.should eq(3)
    end

    it "supports ANSI-256 mode" do
      color = Termisu::Color.ansi256(208)
      color.mode.should eq(Termisu::Color::Mode::ANSI256)
      color.index.should eq(208)
    end

    it "supports RGB mode" do
      color = Termisu::Color.rgb(255, 128, 64)
      color.mode.should eq(Termisu::Color::Mode::RGB)
      color.r.should eq(255)
      color.g.should eq(128)
      color.b.should eq(64)
    end
  end

  describe "Named colors" do
    it "creates basic ANSI-8 colors" do
      Termisu::Color.black.index.should eq(0)
      Termisu::Color.red.index.should eq(1)
      Termisu::Color.green.index.should eq(2)
      Termisu::Color.yellow.index.should eq(3)
      Termisu::Color.blue.index.should eq(4)
      Termisu::Color.magenta.index.should eq(5)
      Termisu::Color.cyan.index.should eq(6)
      Termisu::Color.white.index.should eq(7)
    end

    it "creates bright ANSI-256 colors" do
      Termisu::Color.bright_black.index.should eq(8)
      Termisu::Color.bright_red.index.should eq(9)
      Termisu::Color.bright_green.index.should eq(10)
      Termisu::Color.bright_yellow.index.should eq(11)
      Termisu::Color.bright_blue.index.should eq(12)
      Termisu::Color.bright_magenta.index.should eq(13)
      Termisu::Color.bright_cyan.index.should eq(14)
      Termisu::Color.bright_white.index.should eq(15)
    end

    it "creates default color" do
      color = Termisu::Color.default
      color.default?.should be_true
      color.index.should eq(-1)
    end
  end

  describe "Grayscale colors" do
    it "creates grayscale from 24-step ramp" do
      color = Termisu::Color.grayscale(0)
      color.index.should eq(232)

      color = Termisu::Color.grayscale(23)
      color.index.should eq(255)
    end

    it "validates grayscale level range" do
      expect_raises(ArgumentError, /must be 0-23/) do
        Termisu::Color.grayscale(24)
      end

      expect_raises(ArgumentError, /must be 0-23/) do
        Termisu::Color.grayscale(-1)
      end
    end
  end

  describe "Hex color parsing" do
    it "parses hex colors with hash" do
      color = Termisu::Color.from_hex("#FF8040")
      color.mode.should eq(Termisu::Color::Mode::RGB)
      color.r.should eq(255)
      color.g.should eq(128)
      color.b.should eq(64)
    end

    it "parses hex colors without hash" do
      color = Termisu::Color.from_hex("FF8040")
      color.r.should eq(255)
      color.g.should eq(128)
      color.b.should eq(64)
    end

    it "validates hex format" do
      expect_raises(ArgumentError, /Invalid hex color/) do
        Termisu::Color.from_hex("FFF")
      end
    end
  end

  describe "Color conversions" do
    describe "RGB to ANSI-256" do
      it "converts RGB to nearest ANSI-256 color" do
        color = Termisu::Color.rgb(255, 128, 64)
        ansi256 = color.to_ansi256
        ansi256.mode.should eq(Termisu::Color::Mode::ANSI256)
        ansi256.index.should be >= 16
        ansi256.index.should be <= 231
      end

      it "converts grayscale RGB to grayscale ramp" do
        color = Termisu::Color.rgb(128, 128, 128)
        ansi256 = color.to_ansi256
        ansi256.index.should be >= 232
        ansi256.index.should be <= 255
      end

      it "converts black RGB to grayscale ramp" do
        color = Termisu::Color.rgb(5, 5, 5)
        ansi256 = color.to_ansi256
        ansi256.index.should eq(232)
      end

      it "converts white RGB to grayscale ramp" do
        color = Termisu::Color.rgb(250, 250, 250)
        ansi256 = color.to_ansi256
        ansi256.index.should eq(255)
      end
    end

    describe "RGB to ANSI-8" do
      it "converts bright RGB to high index" do
        color = Termisu::Color.rgb(255, 255, 255)
        ansi8 = color.to_ansi8
        ansi8.index.should eq(7) # White
      end

      it "converts dark RGB to low index" do
        color = Termisu::Color.rgb(0, 0, 0)
        ansi8 = color.to_ansi8
        ansi8.index.should eq(0) # Black
      end

      it "converts RGB red to red" do
        color = Termisu::Color.rgb(200, 50, 50)
        ansi8 = color.to_ansi8
        ansi8.index.should eq(1) # Red
      end

      it "converts RGB green to green" do
        color = Termisu::Color.rgb(50, 200, 50)
        ansi8 = color.to_ansi8
        ansi8.index.should eq(2) # Green
      end

      it "converts RGB blue to blue" do
        color = Termisu::Color.rgb(50, 50, 200)
        ansi8 = color.to_ansi8
        ansi8.index.should eq(4) # Blue
      end
    end

    describe "ANSI-256 to RGB" do
      it "converts ANSI-256 to RGB components" do
        color = Termisu::Color.ansi256(208) # Orange
        r, g, b = color.to_rgb_components
        r.should be > 0
        g.should be > 0
        b.should be >= 0
      end

      it "converts to RGB color" do
        color = Termisu::Color.ansi256(208)
        rgb = color.to_rgb
        rgb.mode.should eq(Termisu::Color::Mode::RGB)
      end
    end

    describe "ANSI-8 to RGB" do
      it "converts ANSI-8 to RGB components" do
        color = Termisu::Color.red
        r, g, b = color.to_rgb_components
        r.should eq(170)
        g.should eq(0)
        b.should eq(0)
      end

      it "converts black" do
        r, g, b = Termisu::Color.black.to_rgb_components
        r.should eq(0)
        g.should eq(0)
        b.should eq(0)
      end

      it "converts white" do
        r, g, b = Termisu::Color.white.to_rgb_components
        r.should eq(170)
        g.should eq(170)
        b.should eq(170)
      end
    end

    describe "ANSI-8 to ANSI-256" do
      it "preserves color index" do
        color = Termisu::Color.red
        ansi256 = color.to_ansi256
        ansi256.index.should eq(1)
      end
    end

    describe "Identity conversions" do
      it "RGB to RGB returns same color" do
        color = Termisu::Color.rgb(255, 128, 64)
        rgb = color.to_rgb
        rgb.r.should eq(255)
        rgb.g.should eq(128)
        rgb.b.should eq(64)
      end

      it "ANSI-256 to ANSI-256 returns same color" do
        color = Termisu::Color.ansi256(208)
        ansi256 = color.to_ansi256
        ansi256.should eq(color)
      end

      it "ANSI-8 to ANSI-8 returns same color" do
        color = Termisu::Color.red
        ansi8 = color.to_ansi8
        ansi8.should eq(color)
      end
    end
  end

  describe "Validation" do
    it "validates ANSI-8 index range" do
      expect_raises(ArgumentError, /must be 0-7 or -1/) do
        Termisu::Color.ansi8(8)
      end

      expect_raises(ArgumentError, /must be 0-7 or -1/) do
        Termisu::Color.ansi8(-2)
      end
    end

    it "validates ANSI-256 index range" do
      expect_raises(ArgumentError, /must be 0-255 or -1/) do
        Termisu::Color.ansi256(256)
      end

      expect_raises(ArgumentError, /must be 0-255 or -1/) do
        Termisu::Color.ansi256(-2)
      end
    end

    it "allows -1 for default color" do
      Termisu::Color.ansi8(-1).default?.should be_true
      Termisu::Color.ansi256(-1).default?.should be_true
    end
  end

  describe "Equality" do
    it "compares ANSI-8 colors by index" do
      color1 = Termisu::Color.red
      color2 = Termisu::Color.ansi8(1)
      color1.should eq(color2)
    end

    it "compares ANSI-256 colors by index" do
      color1 = Termisu::Color.ansi256(208)
      color2 = Termisu::Color.ansi256(208)
      color1.should eq(color2)
    end

    it "compares RGB colors by components" do
      color1 = Termisu::Color.rgb(255, 128, 64)
      color2 = Termisu::Color.rgb(255, 128, 64)
      color1.should eq(color2)
    end

    it "distinguishes different modes" do
      ansi8 = Termisu::Color.red
      rgb = Termisu::Color.rgb(170, 0, 0)
      ansi8.should_not eq(rgb)
    end
  end

  describe "String representation" do
    it "shows ANSI-8 format" do
      Termisu::Color.red.to_s.should contain("ANSI8")
      Termisu::Color.red.to_s.should contain("1")
    end

    it "shows ANSI-256 format" do
      color = Termisu::Color.ansi256(208)
      color.to_s.should contain("ANSI256")
      color.to_s.should contain("208")
    end

    it "shows RGB format" do
      color = Termisu::Color.rgb(255, 128, 64)
      color.to_s.should contain("RGB")
      color.to_s.should contain("255")
      color.to_s.should contain("128")
      color.to_s.should contain("64")
    end
  end

  describe "Default color handling" do
    it "identifies default color" do
      Termisu::Color.default.default?.should be_true
      Termisu::Color.red.default?.should be_false
    end

    it "converts default color to RGB components as black" do
      r, g, b = Termisu::Color.default.to_rgb_components
      r.should eq(0)
      g.should eq(0)
      b.should eq(0)
    end
  end
end
