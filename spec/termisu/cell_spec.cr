require "../spec_helper"

describe Termisu::Cell do
  describe ".new" do
    it "creates a cell with default values" do
      cell = Termisu::Cell.new
      cell.grapheme.should eq(" ")
      cell.fg.should eq(Termisu::Color.white)
      cell.bg.should eq(Termisu::Color.default)
      cell.attr.should eq(Termisu::Attribute::None)
    end

    it "creates a cell with specified character" do
      cell = Termisu::Cell.new("A")
      cell.grapheme.should eq("A")
      cell.fg.should eq(Termisu::Color.white)
      cell.bg.should eq(Termisu::Color.default)
    end

    it "creates a cell with all parameters" do
      cell = Termisu::Cell.new("X", fg: Termisu::Color.green, bg: Termisu::Color.blue, attr: Termisu::Attribute::Bold)
      cell.grapheme.should eq("X")
      cell.fg.should eq(Termisu::Color.green)
      cell.bg.should eq(Termisu::Color.blue)
      cell.attr.should eq(Termisu::Attribute::Bold)
    end

    it "creates a cell with combined attributes" do
      attr = Termisu::Attribute::Bold | Termisu::Attribute::Underline
      cell = Termisu::Cell.new("B", attr: attr)
      cell.attr.bold?.should be_true
      cell.attr.underline?.should be_true
    end

    it "auto-calculates width 2 for CJK character" do
      cell = Termisu::Cell.new("中")
      cell.width.should eq(2u8)
      cell.grapheme.should eq("中")
    end

    it "auto-calculates width 1 for ASCII character" do
      cell = Termisu::Cell.new("A")
      cell.width.should eq(1u8)
      cell.grapheme.should eq("A")
    end
  end

  describe ".default" do
    it "creates a default cell" do
      cell = Termisu::Cell.default
      cell.grapheme.should eq(" ")
      cell.fg.should eq(Termisu::Color.white)
      cell.bg.should eq(Termisu::Color.default)
      cell.attr.should eq(Termisu::Attribute::None)
      cell.width.should eq(1u8)
      cell.continuation?.should be_false
    end
  end

  describe "#==" do
    it "returns true for identical cells" do
      cell1 = Termisu::Cell.new("A", fg: Termisu::Color.green, bg: Termisu::Color.red)
      cell2 = Termisu::Cell.new("A", fg: Termisu::Color.green, bg: Termisu::Color.red)
      cell1.should eq(cell2)
    end

    it "returns false for different characters" do
      cell1 = Termisu::Cell.new("A")
      cell2 = Termisu::Cell.new("B")
      cell1.should_not eq(cell2)
    end

    it "returns false for different foreground colors" do
      cell1 = Termisu::Cell.new("A", fg: Termisu::Color.green)
      cell2 = Termisu::Cell.new("A", fg: Termisu::Color.yellow)
      cell1.should_not eq(cell2)
    end

    it "returns false for different background colors" do
      cell1 = Termisu::Cell.new("A", bg: Termisu::Color.red)
      cell2 = Termisu::Cell.new("A", bg: Termisu::Color.green)
      cell1.should_not eq(cell2)
    end

    it "returns false for different attributes" do
      cell1 = Termisu::Cell.new("A", attr: Termisu::Attribute::Bold)
      cell2 = Termisu::Cell.new("A", attr: Termisu::Attribute::Underline)
      cell1.should_not eq(cell2)
    end
  end

  describe "property setters" do
    it "can modify character" do
      cell = Termisu::Cell.new
      cell.grapheme = "Q"
      cell.grapheme.should eq("Q")
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
      cell.grapheme.should eq("A")
    end

    it "returns space for empty grapheme" do
      cell = Termisu::Cell.new("")
      cell.grapheme.should eq(" ")
    end

    it "grapheme= sets narrow grapheme mode" do
      cell = Termisu::Cell.new("中")
      cell.width.should eq(2u8) # starts wide
      cell.grapheme = "Y"
      cell.grapheme.should eq("Y")
      cell.width.should eq(1u8)
      cell.continuation?.should be_false
    end

    it "grapheme= sets wide grapheme mode for CJK character" do
      cell = Termisu::Cell.new("A")
      cell.width.should eq(1u8) # starts narrow
      cell.grapheme = "中"
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

  describe "single-grapheme cluster fast path" do
    it "stores a CJK cluster as the input String without copying" do
      input = "中"
      cell = Termisu::Cell.new(input)
      cell.grapheme.should be(input)
      cell.width.should eq(2u8)
    end

    it "stores an emoji cluster as the input String without copying" do
      input = "😀"
      cell = Termisu::Cell.new(input)
      cell.grapheme.should be(input)
      cell.width.should eq(2u8)
    end

    it "stores a ZWJ family sequence as one cluster without copying" do
      input = "👨\u{200D}👩\u{200D}👧\u{200D}👦"
      cell = Termisu::Cell.new(input)
      cell.grapheme.should be(input)
      cell.width.should eq(2u8)
    end

    it "stores a regional-indicator flag pair as one cluster without copying" do
      input = "🇺🇸"
      cell = Termisu::Cell.new(input)
      cell.grapheme.should be(input)
      cell.width.should eq(2u8)
    end

    it "stores a combining sequence as one cluster without copying" do
      input = "e\u{0301}"
      cell = Termisu::Cell.new(input)
      cell.grapheme.should be(input)
      cell.width.should eq(1u8)
    end

    it "stores a skin-tone modifier sequence as one cluster without copying" do
      input = "👍\u{1F3FC}"
      cell = Termisu::Cell.new(input)
      cell.grapheme.should be(input)
      cell.width.should eq(2u8)
    end

    it "matches UnicodeWidth.grapheme_width for every cluster type" do
      ["中", "😀", "👨\u{200D}👩\u{200D}👧\u{200D}👦", "🇺🇸", "e\u{0301}", "👍\u{1F3FC}"].each do |grapheme|
        Termisu::Cell.new(grapheme).width.should eq(Termisu::UnicodeWidth.grapheme_width(grapheme))
      end
    end
  end

  describe "ASCII fast path" do
    it "matches UnicodeWidth.grapheme_width for every ASCII codepoint" do
      (0..127).each do |codepoint|
        grapheme = codepoint.chr.to_s
        Termisu::Cell.new(grapheme).width.should eq(Termisu::UnicodeWidth.grapheme_width(grapheme))
      end
    end

    it "assigns width 0 to C0 controls and DEL" do
      Termisu::Cell.new("\u0000").width.should eq(0u8)
      Termisu::Cell.new("\u007f").width.should eq(0u8)
    end

    it "stores a single invalid byte >= 0x80 raw with width 1 via the slow path" do
      cell = Termisu::Cell.new(String.new(Bytes[0xFF_u8]))
      cell.grapheme.bytesize.should eq(1)
      cell.width.should eq(1u8)
    end
  end

  describe "#key" do
    it "is equal exactly when cells are equal" do
      a = Termisu::Cell.new("A", fg: Termisu::Color.green, bg: Termisu::Color.red, attr: Termisu::Attribute::Bold)
      b = Termisu::Cell.new("A", fg: Termisu::Color.green, bg: Termisu::Color.red, attr: Termisu::Attribute::Bold)
      a.key.should eq(b.key)
    end

    it "differs for different grapheme, colors, and attributes" do
      base = Termisu::Cell.new("A")
      Termisu::Cell.new("B").key.should_not eq(base.key)
      Termisu::Cell.new("A", fg: Termisu::Color.red).key.should_not eq(base.key)
      Termisu::Cell.new("A", bg: Termisu::Color.blue).key.should_not eq(base.key)
      Termisu::Cell.new("A", attr: Termisu::Attribute::Bold).key.should_not eq(base.key)
    end

    it "distinguishes same-index colors across modes" do
      ansi8 = Termisu::Cell.new("A", fg: Termisu::Color.ansi8(3))
      ansi256 = Termisu::Cell.new("A", fg: Termisu::Color.ansi256(3))
      ansi8.key.should_not eq(ansi256.key)
    end

    it "accepts the ansi256 default index (-1) without overflow" do
      cell = Termisu::Cell.new("A", fg: Termisu::Color.ansi256(-1), bg: Termisu::Color.ansi256(-1))
      cell.fg.should eq(Termisu::Color.ansi256(-1))
      cell.key.should_not eq(Termisu::Cell.new("A", fg: Termisu::Color.ansi8(-1)).key)
    end

    it "matches for identical RGB colors and differs for different ones" do
      a = Termisu::Cell.new("A", fg: Termisu::Color.rgb(10, 20, 30))
      b = Termisu::Cell.new("A", fg: Termisu::Color.rgb(10, 20, 30))
      c = Termisu::Cell.new("A", fg: Termisu::Color.rgb(10, 20, 31))
      a.key.should eq(b.key)
      a.key.should_not eq(c.key)
    end

    it "interns non-ASCII graphemes consistently" do
      a = Termisu::Cell.new("中")
      b = Termisu::Cell.new(String.new("中".to_slice))
      a.key.should eq(b.key)
      a.key.should_not eq(Termisu::Cell.new("界").key)
    end

    it "distinguishes continuation cells from NUL sentinel cells" do
      sentinel = Termisu::Cell.new("\u0000", fg: Termisu::Color.default, bg: Termisu::Color.default)
      Termisu::Cell.continuation.key.should_not eq(sentinel.key)
    end

    it "is recomputed by property setters" do
      cell = Termisu::Cell.new
      cell.fg = Termisu::Color.yellow
      cell.key.should eq(Termisu::Cell.new(fg: Termisu::Color.yellow).key)
      cell.bg = Termisu::Color.magenta
      cell.attr = Termisu::Attribute::Reverse
      cell.grapheme = "Z"
      expected = Termisu::Cell.new("Z", fg: Termisu::Color.yellow, bg: Termisu::Color.magenta,
        attr: Termisu::Attribute::Reverse)
      cell.key.should eq(expected.key)
    end
  end

  describe "#default_state?" do
    it "is true only for the canonical default cell" do
      Termisu::Cell.new.default_state?.should be_true
      Termisu::Cell.default.default_state?.should be_true
      Termisu::Cell.new("A").default_state?.should be_false
      Termisu::Cell.continuation.default_state?.should be_false
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
