require "spec"
require "../../../src/termisu"
require "../../../src/termisu/testing/screen"

private def screen(cols = 20, rows = 5)
  Termisu::Testing::Screen.new(cols, rows)
end

describe Termisu::Testing::Screen do
  it "places plain text and advances the cursor" do
    s = screen
    s.feed("Hi")
    s.row_text(0).rstrip.should eq("Hi")
    s.cursor_x.should eq(2)
    s.cursor_y.should eq(0)
  end

  it "honors absolute cursor positioning (CUP)" do
    s = screen
    s.feed("\e[2;5HX")
    s.cell(4, 1).grapheme.should eq("X")
    s.cursor_x.should eq(5)
    s.cursor_y.should eq(1)
  end

  it "handles CUP split across feeds" do
    s = screen
    s.feed("\e[")
    s.feed("2;3H")
    s.feed("Z")
    s.cell(2, 1).grapheme.should eq("Z")
  end

  it "applies SGR colors and attributes to written cells" do
    s = screen
    s.feed("\e[31;1mR")
    c = s.cell(0, 0)
    c.grapheme.should eq("R")
    c.fg.should eq(Termisu::Color.ansi8(1))
    c.attr.includes?(Termisu::Attribute::Bold).should be_true
  end

  it "resets the pen on SGR 0" do
    s = screen
    s.feed("\e[31mA\e[0mB")
    s.cell(0, 0).fg.should eq(Termisu::Color.ansi8(1))
    s.cell(1, 0).fg.should eq(Termisu::Color.default)
  end

  it "decodes 256-color and truecolor SGR" do
    s = screen
    s.feed("\e[38;5;208mX\e[38;2;10;20;30mY")
    s.cell(0, 0).fg.should eq(Termisu::Color.ansi256(208))
    s.cell(1, 0).fg.should eq(Termisu::Color.rgb(10, 20, 30))
  end

  it "erases the line (EL 2) and display (ED 2)" do
    s = screen
    s.feed("ABC")
    s.feed("\e[2K")
    s.row_text(0).rstrip.should eq("")

    s.feed("\e[3;1Xhello") # write somewhere then clear all
    s.feed("\e[2J")
    s.row_text(2).rstrip.should eq("")
  end

  it "places wide characters with a continuation cell" do
    s = screen
    s.feed("中")
    lead = s.cell(0, 0)
    lead.grapheme.should eq("中")
    lead.width.should eq(2)
    s.cell(1, 0).continuation?.should be_true
    s.cursor_x.should eq(2)
  end

  it "tracks cursor visibility (civis / cnorm)" do
    s = screen
    s.feed("\e[?25l")
    s.cursor_visible?.should be_false
    s.feed("\e[?12l\e[?25h")
    s.cursor_visible?.should be_true
  end

  it "clears the grid when entering the alternate screen" do
    s = screen
    s.feed("ABC")
    s.feed("\e[?1049h")
    s.row_text(0).rstrip.should eq("")
    s.cursor_x.should eq(0)
  end

  it "locates text by string and regex" do
    s = screen
    s.feed("  hello world")
    s.includes?("hello").should be_true
    s.locate("hello").should eq({2, 0})
    s.locate(/w\w+/).should eq({8, 0})
  end

  it "locates by cell column past wide glyphs (not character offset)" do
    s = screen
    s.feed("中A") # 中 spans columns 0-1, so A sits at column 2 (char offset 1)
    s.locate("A").should eq({2, 0})
    s.locate(/A/).should eq({2, 0})
  end

  it "ignores recognized-but-skipped sequences without corrupting text" do
    s = screen
    # kitty, modifyOtherKeys, mouse, OSC title, then real text
    s.feed("\e[>17u\e[>4;2m\e[?1006h\e]0;title\aOK")
    s.row_text(0).rstrip.should eq("OK")
  end

  it "produces a styled snapshot capturing per-cell fg and attributes" do
    s = screen(10, 2)
    s.feed("\e[31;1mAB\e[0m\e[32mC")
    out = s.to_styled_s
    out.should contain("# styles")
    out.should contain(%(r0 c0-1 "AB" fg=ansi8(1) bg=default attr=Bold))
    out.should contain(%(r0 c2 "C" fg=ansi8(2) bg=default attr=None))
  end

  it "excludes masked regions from styled snapshots" do
    s = screen(20, 1)
    s.feed("\e[31mFrame 7")
    out = s.to_styled_s([/Frame \d+/])
    out.should_not contain("Frame")
    out.should_not contain("ansi8(1)") # masked cells carry no style entry
  end

  it "handles relative cursor moves (CUU/CUD/CUF/CUB) and CHA" do
    s = screen(20, 10)
    s.feed("\e[5;5H") # -> (4, 4)
    s.feed("\e[2A")
    s.cursor_y.should eq(2)
    s.feed("\e[3B")
    s.cursor_y.should eq(5)
    s.feed("\e[4C")
    s.cursor_x.should eq(8)
    s.feed("\e[2D")
    s.cursor_x.should eq(6)
    s.feed("\e[10G") # CHA, column 10 (1-based)
    s.cursor_x.should eq(9)
  end

  it "decodes every SGR attribute code (Dim..Strikethrough)" do
    s = screen(10, 2)
    s.feed("\e[2;3;4;5;7;8;9mX")
    a = s.cell(0, 0).attr
    a.dim?.should be_true
    a.italic?.should be_true
    a.underline?.should be_true
    a.blink?.should be_true
    a.reverse?.should be_true
    a.hidden?.should be_true
    a.strikethrough?.should be_true
  end

  it "renders a 4-byte UTF-8 codepoint (emoji)" do
    s = screen(10, 2)
    s.feed("😀")
    s.cell(0, 0).grapheme.should eq("😀")
  end

  it "recovers from a malformed UTF-8 continuation byte" do
    s = screen(10, 2)
    s.feed(Bytes[0xC3, 0x41]) # lead byte then 'A' (not a continuation)
    s.row_text(0).should contain("A")
  end

  it "tolerates an invalid UTF-8 lead byte" do
    s = screen(10, 2)
    s.feed(Bytes[0xFF, 0x42]) # invalid lead, then 'B'
    s.row_text(0).should contain("B")
  end

  it "consumes an OSC string terminated by ST (ESC backslash)" do
    s = screen(10, 2)
    s.feed("\e]0;my title\e\\OK")
    s.row_text(0).rstrip.should eq("OK")
  end

  it "moves the cursor for newline, tab and autowrap" do
    s = screen(8, 3)
    s.feed("AB\r\nCD") # CR returns to column 0, LF moves down a row
    s.cursor_y.should eq(1)
    s.row_text(1).rstrip.should eq("CD")
    s.feed("\e[3;1H\t") # tab from column 0 clamps to the last column
    s.cursor_x.should eq(7)
    s.feed("\e[1;1HXXXXXXXXY") # 9 glyphs on an 8-wide row wraps
    s.row_text(0).rstrip.should eq("XXXXXXXX")
    s.cursor_y.should eq(1)
  end

  it "erases from the cursor to the end of the display (ED 0)" do
    s = screen(6, 3)
    s.feed("\e[1;1HAAAAAA\e[2;1HBBBBBB\e[3;1HCCCCCC")
    s.feed("\e[2;3H\e[0J")
    s.row_text(0).rstrip.should eq("AAAAAA")
    s.row_text(1).rstrip.should eq("BB")
    s.row_text(2).rstrip.should eq("")
  end

  it "erases from the start of the display to the cursor (ED 1)" do
    s = screen(6, 3)
    s.feed("\e[1;1HAAAAAA\e[2;1HBBBBBB\e[3;1HCCCCCC")
    s.feed("\e[2;4H\e[1J")
    s.row_text(0).rstrip.should eq("")
    s.row_text(1).should eq("    BB")
    s.row_text(2).rstrip.should eq("CCCCCC")
  end

  it "keeps wide glyphs (and skip their continuation cell) in a styled run" do
    s = screen(10, 1)
    s.feed("\e[31m中X")
    s.to_styled_s.should contain(%("中X"))
  end
end
