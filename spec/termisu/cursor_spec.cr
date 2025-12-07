require "../spec_helper"

describe Termisu::Cursor do
  describe ".new" do
    it "creates a hidden cursor by default" do
      cursor = Termisu::Cursor.new
      cursor.hidden?.should be_true
      cursor.x.should eq(-1)
      cursor.y.should eq(-1)
    end
  end

  describe "#set_position" do
    it "sets cursor to specified position and shows it" do
      cursor = Termisu::Cursor.new
      cursor.set_position(10, 5)
      cursor.x.should eq(10)
      cursor.y.should eq(5)
      cursor.visible?.should be_true
    end
  end

  describe "#hide" do
    it "hides the cursor" do
      cursor = Termisu::Cursor.new
      cursor.set_position(10, 5)
      cursor.hide
      cursor.hidden?.should be_true
      cursor.x.should eq(-1)
      cursor.y.should eq(-1)
    end
  end

  describe "#show" do
    it "shows cursor at 0,0 if never positioned" do
      cursor = Termisu::Cursor.new
      cursor.show
      cursor.visible?.should be_true
      cursor.x.should eq(0)
      cursor.y.should eq(0)
    end

    it "keeps current position if already positioned" do
      cursor = Termisu::Cursor.new
      cursor.set_position(5, 3)
      cursor.hide
      cursor.show
      cursor.visible?.should be_true
      cursor.x.should eq(5)
      cursor.y.should eq(3)
    end
  end

  describe "#hidden?" do
    it "returns true when cursor is hidden" do
      cursor = Termisu::Cursor.new
      cursor.hidden?.should be_true

      cursor.set_position(5, 5)
      cursor.hidden?.should be_false

      cursor.hide
      cursor.hidden?.should be_true
    end
  end

  describe "#visible?" do
    it "returns true when cursor is visible" do
      cursor = Termisu::Cursor.new
      cursor.visible?.should be_false

      cursor.set_position(5, 5)
      cursor.visible?.should be_true
    end
  end

  describe "#clamp" do
    it "clamps visible cursor position to bounds" do
      cursor = Termisu::Cursor.new
      cursor.set_position(10, 8)
      cursor.clamp(5, 5)

      cursor.x.should eq(4)
      cursor.y.should eq(4)
      cursor.visible?.should be_true
    end

    it "does not change cursor within bounds" do
      cursor = Termisu::Cursor.new
      cursor.set_position(3, 2)
      cursor.clamp(10, 10)

      cursor.x.should eq(3)
      cursor.y.should eq(2)
    end

    it "clamps negative cursor values to 0" do
      cursor = Termisu::Cursor.new
      cursor.set_position(5, 5)
      # Manually set to test edge case
      cursor.x = -5
      cursor.y = -3
      cursor.clamp(10, 10)

      cursor.x.should eq(0)
      cursor.y.should eq(0)
    end

    it "keeps hidden cursor hidden but clamps last position" do
      cursor = Termisu::Cursor.new
      cursor.set_position(10, 8)
      cursor.hide
      cursor.clamp(5, 5)

      cursor.hidden?.should be_true
      cursor.x.should eq(-1)
      cursor.y.should eq(-1)

      # When shown, should use clamped last position
      cursor.show
      cursor.x.should eq(4)
      cursor.y.should eq(4)
    end

    it "handles zero or negative bounds gracefully" do
      cursor = Termisu::Cursor.new
      cursor.set_position(5, 5)
      cursor.clamp(0, 0)

      # Should not modify cursor when bounds are invalid
      cursor.x.should eq(5)
      cursor.y.should eq(5)
    end

    it "clamps only x when only x is out of bounds" do
      cursor = Termisu::Cursor.new
      cursor.set_position(10, 3)
      cursor.clamp(5, 10)

      cursor.x.should eq(4)
      cursor.y.should eq(3)
    end

    it "clamps only y when only y is out of bounds" do
      cursor = Termisu::Cursor.new
      cursor.set_position(3, 10)
      cursor.clamp(10, 5)

      cursor.x.should eq(3)
      cursor.y.should eq(4)
    end
  end
end
