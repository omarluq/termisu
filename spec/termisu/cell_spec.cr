require "../spec_helper"

describe Termisu::Cell do
  describe ".new" do
    it "creates a cell with default values" do
      cell = Termisu::Cell.new
      cell.ch.should eq(' ')
      cell.fg.should eq(7)
      cell.bg.should eq(-1)
      cell.attr.should eq(Termisu::Attribute::None)
    end

    it "creates a cell with specified character" do
      cell = Termisu::Cell.new('A')
      cell.ch.should eq('A')
      cell.fg.should eq(7)
      cell.bg.should eq(-1)
    end

    it "creates a cell with all parameters" do
      cell = Termisu::Cell.new('X', fg: 2, bg: 4, attr: Termisu::Attribute::Bold)
      cell.ch.should eq('X')
      cell.fg.should eq(2)
      cell.bg.should eq(4)
      cell.attr.should eq(Termisu::Attribute::Bold)
    end

    it "creates a cell with combined attributes" do
      attr = Termisu::Attribute::Bold | Termisu::Attribute::Underline
      cell = Termisu::Cell.new('B', attr: attr)
      cell.attr.bold?.should be_true
      cell.attr.underline?.should be_true
    end
  end

  describe ".default" do
    it "creates a default cell" do
      cell = Termisu::Cell.default
      cell.ch.should eq(' ')
      cell.fg.should eq(7)
      cell.bg.should eq(-1)
      cell.attr.should eq(Termisu::Attribute::None)
    end
  end

  describe "#==" do
    it "returns true for identical cells" do
      cell1 = Termisu::Cell.new('A', fg: 2, bg: 1)
      cell2 = Termisu::Cell.new('A', fg: 2, bg: 1)
      cell1.should eq(cell2)
    end

    it "returns false for different characters" do
      cell1 = Termisu::Cell.new('A')
      cell2 = Termisu::Cell.new('B')
      cell1.should_not eq(cell2)
    end

    it "returns false for different foreground colors" do
      cell1 = Termisu::Cell.new('A', fg: 2)
      cell2 = Termisu::Cell.new('A', fg: 3)
      cell1.should_not eq(cell2)
    end

    it "returns false for different background colors" do
      cell1 = Termisu::Cell.new('A', bg: 1)
      cell2 = Termisu::Cell.new('A', bg: 2)
      cell1.should_not eq(cell2)
    end

    it "returns false for different attributes" do
      cell1 = Termisu::Cell.new('A', attr: Termisu::Attribute::Bold)
      cell2 = Termisu::Cell.new('A', attr: Termisu::Attribute::Underline)
      cell1.should_not eq(cell2)
    end
  end

  describe "#reset" do
    it "resets cell to default state" do
      cell = Termisu::Cell.new('Z', fg: 5, bg: 3, attr: Termisu::Attribute::Bold)
      cell.reset
      cell.ch.should eq(' ')
      cell.fg.should eq(7)
      cell.bg.should eq(-1)
      cell.attr.should eq(Termisu::Attribute::None)
    end
  end

  describe "property setters" do
    it "can modify character" do
      cell = Termisu::Cell.new
      cell.ch = 'Q'
      cell.ch.should eq('Q')
    end

    it "can modify foreground color" do
      cell = Termisu::Cell.new
      cell.fg = 3
      cell.fg.should eq(3)
    end

    it "can modify background color" do
      cell = Termisu::Cell.new
      cell.bg = 5
      cell.bg.should eq(5)
    end

    it "can modify attributes" do
      cell = Termisu::Cell.new
      cell.attr = Termisu::Attribute::Reverse
      cell.attr.should eq(Termisu::Attribute::Reverse)
    end
  end
end
