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

  describe "#move" do
    it "moves cursor to specified position" do
      cursor = Termisu::Cursor.new
      cursor.move(10, 5)
      cursor.x.should eq(10)
      cursor.y.should eq(5)
      cursor.visible?.should be_true
    end
  end

  describe "#hide" do
    it "hides the cursor" do
      cursor = Termisu::Cursor.new
      cursor.move(10, 5)
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
      cursor.move(5, 3)
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

      cursor.move(5, 5)
      cursor.hidden?.should be_false

      cursor.hide
      cursor.hidden?.should be_true
    end
  end

  describe "#visible?" do
    it "returns true when cursor is visible" do
      cursor = Termisu::Cursor.new
      cursor.visible?.should be_false

      cursor.move(5, 5)
      cursor.visible?.should be_true
    end
  end
end
