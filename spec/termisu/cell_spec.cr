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

    it "auto-calculates width 2 for CJK character" do
      cell = Termisu::Cell.new('中')
      cell.width.should eq(2u8)
      cell.grapheme.should eq("中")
    end

    it "auto-calculates width 1 for ASCII character" do
      cell = Termisu::Cell.new('A')
      cell.width.should eq(1u8)
      cell.grapheme.should eq("A")
    end
  end

  describe ".default" do
    it "creates a default cell" do
      cell = Termisu::Cell.default
      cell.ch.should eq(' ')
      cell.fg.should eq(Termisu::Color.white)
      cell.bg.should eq(Termisu::Color.default)
      cell.attr.should eq(Termisu::Attribute::None)
      cell.width.should eq(1u8)
      cell.continuation?.should be_false
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
      cell.width.should eq(1u8)
      cell.continuation?.should be_false
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

  describe "grapheme and width properties" do
    it "stores grapheme as String" do
      cell = Termisu::Cell.new("A")
      cell.grapheme.should eq("A")
    end

    it "auto-calculates width for narrow characters" do
      cell = Termisu::Cell.new("A")
      cell.width.should eq(1u8)
    end

    it "auto-calculates width for wide characters" do
      cell = Termisu::Cell.new("中")
      cell.width.should eq(2u8)
    end

    it "auto-calculates width for emoji" do
      cell = Termisu::Cell.new("😀")
      cell.width.should eq(2u8)
    end

    it "stores continuation flag" do
      cell = Termisu::Cell.new("A")
      cell.continuation?.should be_false
    end
  end

  describe ".continuation" do
    it "creates a continuation cell" do
      cell = Termisu::Cell.continuation
      cell.continuation?.should be_true
      cell.width.should eq(0u8)
      cell.grapheme.should eq("")
    end

    it "returns space for ch on continuation cell" do
      cell = Termisu::Cell.continuation
      cell.ch.should eq(' ')
    end

    it "normalizes non-empty grapheme to empty for continuation" do
      # Even if grapheme text is passed, continuation cells are always empty
      cell = Termisu::Cell.new("X", continuation: true)
      cell.grapheme.should eq("")
      cell.width.should eq(0u8)
      cell.continuation?.should be_true
    end
  end

  describe "compatibility ch property" do
    it "returns first character for normal cells" do
      cell = Termisu::Cell.new("ABC")
      cell.ch.should eq('A')
    end

    it "returns space for empty grapheme" do
      cell = Termisu::Cell.new("")
      cell.ch.should eq(' ')
    end

    it "returns space for continuation cells" do
      cell = Termisu::Cell.continuation
      cell.ch.should eq(' ')
    end

    it "ch= sets narrow grapheme mode" do
      cell = Termisu::Cell.new("中")
      cell.width.should eq(2u8) # starts wide
      cell.ch = 'Y'
      cell.grapheme.should eq("Y")
      cell.width.should eq(1u8)
      cell.continuation?.should be_false
    end

    it "ch= sets wide grapheme mode for CJK character" do
      cell = Termisu::Cell.new('A')
      cell.width.should eq(1u8) # starts narrow
      cell.ch = '中'
      cell.grapheme.should eq("中")
      cell.width.should eq(2u8)
      cell.continuation?.should be_false
    end
  end

  describe "multi-grapheme truncation" do
    it "stores only first grapheme from multi-grapheme string" do
      cell = Termisu::Cell.new("AB")
      cell.grapheme.should eq("A")
      cell.width.should eq(1u8)
    end

    it "stores first wide grapheme from mixed string" do
      cell = Termisu::Cell.new("中A")
      cell.grapheme.should eq("中")
      cell.width.should eq(2u8)
    end

    it "preserves combining sequence as single grapheme" do
      # e + combining acute is one grapheme cluster
      cell = Termisu::Cell.new("e\u{0301}X")
      cell.grapheme.should eq("e\u{0301}")
      cell.width.should eq(1u8)
    end
  end

  describe "#== with new fields" do
    it "returns false for different grapheme" do
      cell1 = Termisu::Cell.new("A")
      cell2 = Termisu::Cell.new("B")
      cell1.should_not eq(cell2)
    end

    it "returns false for narrow vs wide grapheme" do
      cell1 = Termisu::Cell.new("A")
      cell2 = Termisu::Cell.new("中")
      cell1.should_not eq(cell2)
      cell1.width.should_not eq(cell2.width)
    end

    it "returns false when one is continuation" do
      cell1 = Termisu::Cell.new("A")
      cell2 = Termisu::Cell.continuation
      cell1.should_not eq(cell2)
    end

    it "returns true for identical wide cells" do
      cell1 = Termisu::Cell.new("中")
      cell2 = Termisu::Cell.new("中")
      cell1.should eq(cell2)
      cell1.width.should eq(2u8)
    end
  end
end
