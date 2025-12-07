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
end
