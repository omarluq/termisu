require "../spec_helper"

describe Termisu::Buffer do
  describe ".new" do
    it "creates a buffer with specified dimensions" do
      buffer = Termisu::Buffer.new(80, 24)
      buffer.width.should eq(80)
      buffer.height.should eq(24)
    end

    it "initializes all cells to default" do
      buffer = Termisu::Buffer.new(10, 5)
      cell = buffer.get_cell(0, 0)
      cell.should_not be_nil
      cell.as(Termisu::Cell).ch.should eq(' ')
      cell.as(Termisu::Cell).fg.should eq(Termisu::Color.white)
      cell.as(Termisu::Cell).bg.should eq(Termisu::Color.default)
    end
  end

  describe "#set_cell" do
    it "sets a cell at valid coordinates" do
      buffer = Termisu::Buffer.new(10, 5)
      result = buffer.set_cell(5, 2, 'A', fg: Termisu::Color.green, bg: Termisu::Color.red)
      result.should be_true

      cell = buffer.get_cell(5, 2)
      cell.should_not be_nil
      cell.as(Termisu::Cell).ch.should eq('A')
      cell.as(Termisu::Cell).fg.should eq(Termisu::Color.green)
      cell.as(Termisu::Cell).bg.should eq(Termisu::Color.red)
    end

    it "returns false for out of bounds x" do
      buffer = Termisu::Buffer.new(10, 5)
      buffer.set_cell(-1, 2, 'A').should be_false
      buffer.set_cell(10, 2, 'A').should be_false
    end

    it "returns false for out of bounds y" do
      buffer = Termisu::Buffer.new(10, 5)
      buffer.set_cell(5, -1, 'A').should be_false
      buffer.set_cell(5, 5, 'A').should be_false
    end

    it "returns false for C0 control characters (except space)" do
      buffer = Termisu::Buffer.new(10, 5)
      buffer.set_cell(0, 0, '\u{0}').should be_false  # NUL
      buffer.set_cell(0, 0, '\u{1}').should be_false  # SOH
      buffer.set_cell(0, 0, '\t').should be_false     # Tab
      buffer.set_cell(0, 0, '\n').should be_false     # Newline
      buffer.set_cell(0, 0, '\r').should be_false     # Carriage return
      buffer.set_cell(0, 0, '\u{1F}').should be_false # US
    end

    it "returns false for C1 control characters" do
      buffer = Termisu::Buffer.new(10, 5)
      buffer.set_cell(0, 0, '\u{7F}').should be_false # DEL
      buffer.set_cell(0, 0, '\u{80}').should be_false # PAD
      buffer.set_cell(0, 0, '\u{9F}').should be_false # APC
    end

    it "returns false for standalone combining marks (width 0)" do
      buffer = Termisu::Buffer.new(10, 5)
      buffer.set_cell(0, 0, '\u{0301}').should be_false # Combining acute accent
      buffer.set_cell(0, 0, '\u{0300}').should be_false # Combining grave accent
      buffer.set_cell(0, 0, '\u{0303}').should be_false # Combining tilde
    end

    it "does not mutate neighboring cells when rejecting width-0 write" do
      buffer = Termisu::Buffer.new(10, 5)
      buffer.set_cell(0, 0, 'A')
      buffer.set_cell(1, 0, 'B')

      # Width-0 write at position 0 should be rejected without side effects
      buffer.set_cell(0, 0, '\u{0301}').should be_false

      # Adjacent cells should remain intact
      cell0 = buffer.get_cell(0, 0)
      cell1 = buffer.get_cell(1, 0)
      cell0.as(Termisu::Cell).ch.should eq('A')
      cell1.as(Termisu::Cell).ch.should eq('B')
    end

    it "returns true for space (0x20)" do
      buffer = Termisu::Buffer.new(10, 5)
      buffer.set_cell(0, 0, ' ').should be_true
      cell = buffer.get_cell(0, 0)
      cell.as(Termisu::Cell).ch.should eq(' ')
    end

    it "returns true for printable characters above 0x20" do
      buffer = Termisu::Buffer.new(10, 5)
      buffer.set_cell(0, 0, '!').should be_true # 0x21
      buffer.set_cell(0, 0, 'A').should be_true # 0x41
      buffer.set_cell(0, 0, '~').should be_true # 0x7E
    end

    it "sets cell with attributes" do
      buffer = Termisu::Buffer.new(10, 5)
      buffer.set_cell(3, 3, 'B', attr: Termisu::Attribute::Bold)

      cell = buffer.get_cell(3, 3)
      cell.as(Termisu::Cell).attr.should eq(Termisu::Attribute::Bold)
    end
  end

  describe "#get_cell" do
    it "gets a cell at valid coordinates" do
      buffer = Termisu::Buffer.new(10, 5)
      buffer.set_cell(4, 2, 'X')
      cell = buffer.get_cell(4, 2)
      cell.should_not be_nil
      cell.as(Termisu::Cell).ch.should eq('X')
    end

    it "returns nil for out of bounds" do
      buffer = Termisu::Buffer.new(10, 5)
      buffer.get_cell(-1, 2).should be_nil
      buffer.get_cell(10, 2).should be_nil
      buffer.get_cell(5, -1).should be_nil
      buffer.get_cell(5, 5).should be_nil
    end
  end

  describe "#clear" do
    it "resets all cells to default" do
      buffer = Termisu::Buffer.new(10, 5)
      buffer.set_cell(3, 2, 'A', fg: Termisu::Color.green, bg: Termisu::Color.red)
      buffer.clear

      cell = buffer.get_cell(3, 2)
      cell.as(Termisu::Cell).ch.should eq(' ')
      cell.as(Termisu::Cell).fg.should eq(Termisu::Color.white)
      cell.as(Termisu::Cell).bg.should eq(Termisu::Color.default)
    end
  end

  describe "#invalidate" do
    it "forces full re-render on next render_to" do
      renderer = MockRenderer.new
      buffer = Termisu::Buffer.new(5, 2)

      # Initial render - sets content
      buffer.set_cell(0, 0, 'A')
      buffer.render_to(renderer)

      # Clear renderer and render again - no changes, should render nothing new
      renderer.clear
      buffer.render_to(renderer)
      renderer.write_calls.should be_empty

      # Invalidate and render again - should render the 'A' again
      renderer.clear
      buffer.invalidate
      buffer.render_to(renderer)
      # Write calls contain batched strings, check that 'A' is in one of them
      renderer.write_calls.any?(&.includes?('A')).should be_true
    end
  end

  describe "#render_to (diff-based rendering)" do
    it "only renders changed cells" do
      renderer = MockRenderer.new
      buffer = Termisu::Buffer.new(5, 3)

      # First render - set up initial state
      buffer.set_cell(2, 1, 'A')
      buffer.render_to(renderer)

      # Clear tracking for second render
      renderer.clear

      # Change a non-adjacent cell to force cursor move
      buffer.set_cell(0, 2, 'B')
      buffer.render_to(renderer)

      # Should only render 1 cell (the changed one)
      renderer.write_calls.should contain("B")
      renderer.move_calls.should contain({0, 2})
    end

    it "skips cursor movement when cursor is already at correct position" do
      renderer = MockRenderer.new
      buffer = Termisu::Buffer.new(5, 3)

      # First render - set up initial state
      buffer.set_cell(2, 1, 'A')
      buffer.render_to(renderer)

      # Clear tracking
      renderer.clear

      # Write at position where cursor already is (right after 'A')
      buffer.set_cell(3, 1, 'B')
      buffer.render_to(renderer)

      # Should write 'B' but no cursor move needed (cursor advanced from writing 'A')
      renderer.write_calls.should contain("B")
      renderer.move_calls.should be_empty # Optimization: cursor already at right position
    end

    it "calls renderer.flush after rendering" do
      renderer = MockRenderer.new
      buffer = Termisu::Buffer.new(5, 3)

      buffer.render_to(renderer)
      renderer.flush_count.should eq(1)
    end

    it "renders colors for changed cells" do
      renderer = MockRenderer.new
      buffer = Termisu::Buffer.new(5, 3)

      buffer.set_cell(2, 1, 'X', fg: Termisu::Color.yellow, bg: Termisu::Color.magenta)
      buffer.render_to(renderer)

      renderer.fg_calls.should contain(Termisu::Color.yellow)
      renderer.bg_calls.should contain(Termisu::Color.magenta)
    end

    it "renders attributes for changed cells" do
      renderer = MockRenderer.new
      buffer = Termisu::Buffer.new(5, 3)

      buffer.set_cell(2, 1, 'B', attr: Termisu::Attribute::Bold)
      buffer.render_to(renderer)

      renderer.bold_count.should be > 0
    end

    it "batches consecutive cells with same styling" do
      renderer = MockRenderer.new
      buffer = Termisu::Buffer.new(10, 3)

      # Set 3 consecutive cells with same styling
      buffer.set_cell(2, 1, 'A', fg: Termisu::Color.green)
      buffer.set_cell(3, 1, 'B', fg: Termisu::Color.green)
      buffer.set_cell(4, 1, 'C', fg: Termisu::Color.green)
      buffer.render_to(renderer)

      # Clear and set up for diff test
      renderer.clear

      # Change same cells again
      buffer.set_cell(2, 1, 'X', fg: Termisu::Color.red)
      buffer.set_cell(3, 1, 'Y', fg: Termisu::Color.red)
      buffer.set_cell(4, 1, 'Z', fg: Termisu::Color.red)
      buffer.render_to(renderer)

      # Should batch into single write "XYZ"
      renderer.write_calls.should contain("XYZ")
      # Should only set color once (not 3 times)
      renderer.fg_calls.size.should eq(1)
      renderer.fg_calls[0].should eq(Termisu::Color.red)
    end

    it "splits batches when styling changes" do
      renderer = MockRenderer.new
      buffer = Termisu::Buffer.new(10, 3)

      # Set cells with different colors
      buffer.set_cell(2, 1, 'A', fg: Termisu::Color.green)
      buffer.set_cell(3, 1, 'B', fg: Termisu::Color.red) # Different color
      buffer.set_cell(4, 1, 'C', fg: Termisu::Color.red) # Same as B
      buffer.render_to(renderer)

      # Should have separate writes for different styles
      renderer.write_calls.should contain("A")
      renderer.write_calls.should contain("BC")
    end
  end

  describe "#sync_to (full redraw)" do
    it "renders all cells regardless of changes" do
      renderer = MockRenderer.new
      buffer = Termisu::Buffer.new(3, 2)

      # Set one cell
      buffer.set_cell(1, 1, 'A')

      # First render
      buffer.render_to(renderer)

      # Clear tracking
      renderer.write_calls.clear

      # Sync should render all 6 cells (3x2)
      # With batching, cells with same style are batched together
      buffer.sync_to(renderer)

      # Total characters rendered should equal total cells
      total_chars = renderer.write_calls.sum(&.size)
      total_chars.should eq(6)
      renderer.flush_count.should eq(2) # render_to + sync_to
    end

    it "batches cells with same styling on sync" do
      renderer = MockRenderer.new
      buffer = Termisu::Buffer.new(5, 1)

      # All default cells - should batch into single write
      buffer.sync_to(renderer)

      # All 5 cells should be in a single batched write
      renderer.write_calls.size.should eq(1)
      renderer.write_calls[0].size.should eq(5)
    end
  end

  describe "#resize" do
    it "preserves existing content when growing" do
      buffer = Termisu::Buffer.new(5, 3)
      buffer.set_cell(2, 1, 'A')

      buffer.resize(10, 5)

      buffer.width.should eq(10)
      buffer.height.should eq(5)

      # Old content preserved
      cell = buffer.get_cell(2, 1)
      cell.as(Termisu::Cell).ch.should eq('A')

      # New area has default cells
      new_cell = buffer.get_cell(8, 4)
      new_cell.as(Termisu::Cell).ch.should eq(' ')
    end

    it "preserves existing content when shrinking" do
      buffer = Termisu::Buffer.new(10, 5)
      buffer.set_cell(2, 1, 'B')
      buffer.set_cell(8, 4, 'X') # Will be lost

      buffer.resize(5, 3)

      buffer.width.should eq(5)
      buffer.height.should eq(3)

      # Content within new bounds preserved
      cell = buffer.get_cell(2, 1)
      cell.as(Termisu::Cell).ch.should eq('B')

      # Content outside new bounds inaccessible
      buffer.get_cell(8, 4).should be_nil
    end

    it "does nothing if size unchanged" do
      buffer = Termisu::Buffer.new(10, 5)
      buffer.set_cell(3, 2, 'C')

      buffer.resize(10, 5)

      buffer.width.should eq(10)
      buffer.height.should eq(5)

      cell = buffer.get_cell(3, 2)
      cell.as(Termisu::Cell).ch.should eq('C')
    end

    it "clamps cursor position when shrinking" do
      buffer = Termisu::Buffer.new(10, 8)
      buffer.set_cursor(8, 6)

      buffer.resize(5, 4)

      buffer.cursor.x.should eq(4)
      buffer.cursor.y.should eq(3)
      buffer.cursor.visible?.should be_true
    end

    it "preserves cursor position when growing" do
      buffer = Termisu::Buffer.new(10, 8)
      buffer.set_cursor(5, 4)

      buffer.resize(20, 16)

      buffer.cursor.x.should eq(5)
      buffer.cursor.y.should eq(4)
    end

    it "clamps hidden cursor's last position when shrinking" do
      buffer = Termisu::Buffer.new(10, 8)
      buffer.set_cursor(8, 6)
      buffer.hide_cursor

      buffer.resize(5, 4)

      buffer.cursor.hidden?.should be_true

      # When shown, should be at clamped position
      buffer.show_cursor
      buffer.cursor.x.should eq(4)
      buffer.cursor.y.should eq(3)
    end
  end

  describe "#set_cursor" do
    it "sets cursor to valid position" do
      buffer = Termisu::Buffer.new(10, 8)
      buffer.set_cursor(5, 4)

      buffer.cursor.x.should eq(5)
      buffer.cursor.y.should eq(4)
      buffer.cursor.visible?.should be_true
    end

    it "clamps cursor x to buffer width" do
      buffer = Termisu::Buffer.new(10, 8)
      buffer.set_cursor(15, 4)

      buffer.cursor.x.should eq(9)
      buffer.cursor.y.should eq(4)
    end

    it "clamps cursor y to buffer height" do
      buffer = Termisu::Buffer.new(10, 8)
      buffer.set_cursor(5, 12)

      buffer.cursor.x.should eq(5)
      buffer.cursor.y.should eq(7)
    end

    it "clamps negative x to 0" do
      buffer = Termisu::Buffer.new(10, 8)
      buffer.set_cursor(-5, 4)

      buffer.cursor.x.should eq(0)
      buffer.cursor.y.should eq(4)
    end

    it "clamps negative y to 0" do
      buffer = Termisu::Buffer.new(10, 8)
      buffer.set_cursor(5, -3)

      buffer.cursor.x.should eq(5)
      buffer.cursor.y.should eq(0)
    end

    it "clamps both coordinates when both out of bounds" do
      buffer = Termisu::Buffer.new(10, 8)
      buffer.set_cursor(100, 100)

      buffer.cursor.x.should eq(9)
      buffer.cursor.y.should eq(7)
    end
  end

  describe "cursor rendering" do
    it "renders visible cursor" do
      renderer = MockRenderer.new
      buffer = Termisu::Buffer.new(5, 3)
      buffer.set_cursor(2, 1)

      buffer.render_to(renderer)

      renderer.show_cursor_count.should eq(1)
      renderer.move_calls.should contain({2, 1})
    end

    it "renders hidden cursor" do
      renderer = MockRenderer.new
      buffer = Termisu::Buffer.new(5, 3)
      buffer.hide_cursor

      buffer.render_to(renderer)

      renderer.hide_cursor_count.should eq(1)
    end
  end

  describe "wide character write semantics" do
    it "creates leading cell with width 2 and continuation cell" do
      buffer = Termisu::Buffer.new(10, 2)
      buffer.set_cell(5, 0, '中')

      lead = buffer.get_cell(5, 0)
      trail = buffer.get_cell(6, 0)

      lead.should_not be_nil
      trail.should_not be_nil

      lead.as(Termisu::Cell).grapheme.should eq("中")
      lead.as(Termisu::Cell).width.should eq(2u8)
      lead.as(Termisu::Cell).continuation?.should be_false

      trail.as(Termisu::Cell).grapheme.should eq("")
      trail.as(Termisu::Cell).width.should eq(0u8)
      trail.as(Termisu::Cell).continuation?.should be_true
    end

    it "rejects wide character at last column" do
      buffer = Termisu::Buffer.new(10, 2)

      # Width 2 character at column 9 (last column) cannot fit
      buffer.set_cell(9, 0, '中').should be_false

      # Column should remain default
      cell = buffer.get_cell(9, 0)
      cell.as(Termisu::Cell).ch.should eq(' ')
    end

    it "rejects wide character at column width-1" do
      buffer = Termisu::Buffer.new(80, 24)

      # Width 2 character at column 79 (last column) cannot fit
      buffer.set_cell(79, 0, '中').should be_false
    end

    it "accepts wide character with room for continuation" do
      buffer = Termisu::Buffer.new(10, 2)

      # Width 2 character at column 8 has room for continuation at 9
      buffer.set_cell(8, 0, '中').should be_true

      lead = buffer.get_cell(8, 0)
      trail = buffer.get_cell(9, 0)

      lead.as(Termisu::Cell).width.should eq(2u8)
      trail.as(Termisu::Cell).continuation?.should be_true
    end
  end

  describe "overlap clearing" do
    it "clears wide cell continuation when overwriting leading cell" do
      buffer = Termisu::Buffer.new(10, 2)
      buffer.set_cell(5, 0, '中')

      # Overwrite leading cell with narrow
      buffer.set_cell(5, 0, 'A')

      cell = buffer.get_cell(6, 0)
      cell.as(Termisu::Cell).continuation?.should be_false
      cell.as(Termisu::Cell).ch.should eq(' ')
    end

    it "clears owner when writing into continuation cell" do
      buffer = Termisu::Buffer.new(10, 2)
      buffer.set_cell(5, 0, '中')

      # Write into the continuation cell
      buffer.set_cell(6, 0, 'X')

      # Leading cell should be cleared
      lead = buffer.get_cell(5, 0)
      lead.as(Termisu::Cell).ch.should eq(' ')
      lead.as(Termisu::Cell).width.should eq(1u8)
    end

    it "clears continuation when writing narrow overlapping next position" do
      buffer = Termisu::Buffer.new(10, 2)
      buffer.set_cell(5, 0, '中')

      # Write narrow character that overlaps the continuation
      buffer.set_cell(6, 0, 'B')

      # Leading cell should remain, but its continuation is cleared
      # This leaves an orphan leading cell, which is then handled
      lead = buffer.get_cell(5, 0)
      trail = buffer.get_cell(6, 0)

      lead.as(Termisu::Cell).ch.should eq(' ')
      trail.as(Termisu::Cell).ch.should eq('B')
    end

    it "clears orphan continuation when wide-over-wide overwrite overlaps leading cell (BUG-008)" do
      buffer = Termisu::Buffer.new(10, 2)

      # Write wide at position 6 (leads at 6, continuation at 7)
      buffer.set_cell(6, 0, '中')

      # Write wide at position 5 (leads at 5, continuation at 6)
      # This overwrites the leading cell of the previous wide char at 6
      buffer.set_cell(5, 0, '日')

      # Position 5 should be new wide char leading
      lead5 = buffer.get_cell(5, 0)
      lead5.as(Termisu::Cell).ch.should eq('日')
      lead5.as(Termisu::Cell).width.should eq(2u8)

      # Position 6 should be continuation of new wide char
      trail6 = buffer.get_cell(6, 0)
      trail6.as(Termisu::Cell).continuation?.should be_true

      # Position 7 should NOT be orphan continuation (must be default)
      cell7 = buffer.get_cell(7, 0)
      cell7.as(Termisu::Cell).ch.should eq(' ')
      cell7.as(Termisu::Cell).continuation?.should be_false
      cell7.as(Termisu::Cell).width.should eq(1u8)
    end

    it "clears orphan continuation when wide-over-wide overwrite overlaps continuation cell (BUG-008)" do
      buffer = Termisu::Buffer.new(10, 2)

      # Write wide at position 5 (leads at 5, continuation at 6)
      buffer.set_cell(5, 0, '中')

      # Write narrow at position 7
      buffer.set_cell(7, 0, 'X')

      # Write wide at position 6 (leads at 6, continuation at 7)
      # Position 7 has narrow 'X', not a wide lead, so no x+2 to clear
      buffer.set_cell(6, 0, '日')

      # Position 5 (old wide lead) should be cleared
      cell5 = buffer.get_cell(5, 0)
      cell5.as(Termisu::Cell).ch.should eq(' ')
      cell5.as(Termisu::Cell).width.should eq(1u8)

      # Position 6 should be new wide char leading
      lead6 = buffer.get_cell(6, 0)
      lead6.as(Termisu::Cell).ch.should eq('日')
      lead6.as(Termisu::Cell).width.should eq(2u8)

      # Position 7 should be continuation of new wide char
      trail7 = buffer.get_cell(7, 0)
      trail7.as(Termisu::Cell).continuation?.should be_true
    end
  end

  describe "clear and occupancy invariants" do
    it "clear removes all content including continuation cells" do
      buffer = Termisu::Buffer.new(10, 2)
      buffer.set_cell(5, 0, '中')
      buffer.set_cell(7, 0, '日')

      buffer.clear

      10.times do |i|
        cell = buffer.get_cell(i, 0)
        cell.as(Termisu::Cell).ch.should eq(' ')
        cell.as(Termisu::Cell).width.should eq(1u8)
        cell.as(Termisu::Cell).continuation?.should be_false
      end
    end

    it "clear produces only default cells (no orphans)" do
      buffer = Termisu::Buffer.new(20, 5)
      buffer.set_cell(5, 2, '中')

      buffer.clear

      # Verify no orphan continuation cells exist
      20.times do |x|
        5.times do |y|
          cell = buffer.get_cell(x, y)
          cell.as(Termisu::Cell).continuation?.should be_false
        end
      end
    end
  end

  describe "resize and occupancy invariants" do
    it "removes orphan continuation cells when shrinking width" do
      buffer = Termisu::Buffer.new(10, 2)
      buffer.set_cell(8, 0, '中') # Wide cell at 8, continuation at 9

      buffer.resize(8, 2)

      # Continuation at position 9 is gone (out of bounds)
      # Leading cell at 8 should be default (cannot be wide without continuation)
      cell = buffer.get_cell(7, 0) # Column 7 was originally position 8
      cell.as(Termisu::Cell).ch.should eq(' ')
    end

    it "removes wide cells at new last column" do
      buffer = Termisu::Buffer.new(10, 2)
      buffer.set_cell(8, 0, '中') # Wide at 8, continuation at 9

      buffer.resize(9, 2)

      # Wide cell at column 8 cannot have continuation (new last column)
      # Should be replaced with default
      cell = buffer.get_cell(8, 0)
      cell.as(Termisu::Cell).width.should eq(1u8)
      cell.as(Termisu::Cell).ch.should eq(' ')
    end

    it "preserves valid wide cells when growing" do
      buffer = Termisu::Buffer.new(5, 2)
      buffer.set_cell(3, 0, '中')

      buffer.resize(10, 2)

      lead = buffer.get_cell(3, 0)
      trail = buffer.get_cell(4, 0)

      lead.as(Termisu::Cell).width.should eq(2u8)
      trail.as(Termisu::Cell).continuation?.should be_true
    end

    it "produces no orphan continuation cells after resize" do
      buffer = Termisu::Buffer.new(10, 5)

      # Create some wide cells
      buffer.set_cell(2, 0, '中')
      buffer.set_cell(5, 2, '日')

      buffer.resize(8, 3)

      # Verify no orphan continuation cells exist
      8.times do |x|
        3.times do |y|
          cell = buffer.get_cell(x, y)
          if cell.as(Termisu::Cell).continuation?
            # Must have a valid leading cell
            if x > 0
              lead = buffer.get_cell(x - 1, y)
              lead.as(Termisu::Cell).width.should eq(2u8)
            end
          end
        end
      end
    end
  end
end
