require "../spec_helper"

describe Termisu::Cell do
  describe ".new" do
    it "creates a cell with default values" do
      cell = Termisu::Cell.new
      cell.ch.should eq(' ')
      cell.fg.should eq(Termisu::Color.white)
      cell.bg.should eq(Termisu::Color.default)
      cell.attr.should eq(Termisu::Attribute::None)
    end

    it "creates a cell with specified character" do
      cell = Termisu::Cell.new('A')
      cell.ch.should eq('A')
      cell.fg.should eq(Termisu::Color.white)
      cell.bg.should eq(Termisu::Color.default)
    end

    it "creates a cell with all parameters" do
      cell = Termisu::Cell.new('X', fg: Termisu::Color.green, bg: Termisu::Color.blue, attr: Termisu::Attribute::Bold)
      cell.ch.should eq('X')
      cell.fg.should eq(Termisu::Color.green)
      cell.bg.should eq(Termisu::Color.blue)
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
      cell.fg.should eq(Termisu::Color.white)
      cell.bg.should eq(Termisu::Color.default)
      cell.attr.should eq(Termisu::Attribute::None)
    end
  end

  describe "#==" do
    it "returns true for identical cells" do
      cell1 = Termisu::Cell.new('A', fg: Termisu::Color.green, bg: Termisu::Color.red)
      cell2 = Termisu::Cell.new('A', fg: Termisu::Color.green, bg: Termisu::Color.red)
      cell1.should eq(cell2)
    end

    it "returns false for different characters" do
      cell1 = Termisu::Cell.new('A')
      cell2 = Termisu::Cell.new('B')
      cell1.should_not eq(cell2)
    end

    it "returns false for different foreground colors" do
      cell1 = Termisu::Cell.new('A', fg: Termisu::Color.green)
      cell2 = Termisu::Cell.new('A', fg: Termisu::Color.yellow)
      cell1.should_not eq(cell2)
    end

    it "returns false for different background colors" do
      cell1 = Termisu::Cell.new('A', bg: Termisu::Color.red)
      cell2 = Termisu::Cell.new('A', bg: Termisu::Color.green)
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
      cell = Termisu::Cell.new(
        'Z',
        fg: Termisu::Color.magenta,
        bg: Termisu::Color.yellow,
        attr: Termisu::Attribute::Bold
      )
      cell.reset
      cell.ch.should eq(' ')
      cell.fg.should eq(Termisu::Color.white)
      cell.bg.should eq(Termisu::Color.default)
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
      cell.fg = Termisu::Color.yellow
      cell.fg.should eq(Termisu::Color.yellow)
    end

    it "can modify background color" do
      cell = Termisu::Cell.new
      cell.bg = Termisu::Color.magenta
      cell.bg.should eq(Termisu::Color.magenta)
    end

    it "can modify attributes" do
      cell = Termisu::Cell.new
      cell.attr = Termisu::Attribute::Reverse
      cell.attr.should eq(Termisu::Attribute::Reverse)
    end
  end
end
