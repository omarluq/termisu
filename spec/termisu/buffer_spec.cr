require "../spec_helper"

# Mock backend for testing buffer rendering
class MockBufferBackend < Termisu::Backend
  property write_calls : Array(String) = [] of String
  property move_calls : Array({Int32, Int32}) = [] of {Int32, Int32}
  property fg_calls : Array(Termisu::Color) = [] of Termisu::Color
  property bg_calls : Array(Termisu::Color) = [] of Termisu::Color
  property flush_count : Int32 = 0
  property reset_count : Int32 = 0
  property bold_count : Int32 = 0
  property underline_count : Int32 = 0
  property show_cursor_count : Int32 = 0
  property hide_cursor_count : Int32 = 0

  def write(data : String)
    @write_calls << data
  end

  def move_cursor(x : Int32, y : Int32)
    @move_calls << {x, y}
  end

  def foreground=(color : Termisu::Color)
    @fg_calls << color
  end

  def background=(color : Termisu::Color)
    @bg_calls << color
  end

  def flush
    @flush_count += 1
  end

  def reset_attributes
    @reset_count += 1
  end

  def enable_bold
    @bold_count += 1
  end

  def enable_underline
    @underline_count += 1
  end

  def enable_blink; end

  def enable_reverse; end

  def show_cursor
    @show_cursor_count += 1
  end

  def hide_cursor
    @hide_cursor_count += 1
  end

  def size : {Int32, Int32}
    {80, 24}
  end

  def close; end
end

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

  describe "#flush (diff-based rendering)" do
    it "only renders changed cells" do
      backend = MockBufferBackend.new
      buffer = Termisu::Buffer.new(5, 3)

      # First flush - all cells rendered (front buffer empty)
      buffer.set_cell(2, 1, 'A')
      buffer.flush(backend)

      # Second flush - only changed cell rendered
      backend.write_calls.clear
      backend.move_calls.clear

      # Change a non-adjacent cell to force cursor move
      buffer.set_cell(0, 2, 'B')
      buffer.flush(backend)

      # Should only render 1 cell (the changed one)
      backend.write_calls.size.should eq(1)
      backend.write_calls.should contain("B")
      backend.move_calls.should contain({0, 2})
    end

    it "skips cursor movement when cursor is already at correct position" do
      backend = MockBufferBackend.new
      buffer = Termisu::Buffer.new(5, 3)

      # First flush - set up initial state
      buffer.set_cell(2, 1, 'A')
      buffer.flush(backend)

      # Clear tracking
      backend.write_calls.clear
      backend.move_calls.clear

      # Write at position where cursor already is (right after 'A')
      buffer.set_cell(3, 1, 'B')
      buffer.flush(backend)

      # Should write 'B' but no cursor move needed (cursor advanced from writing 'A')
      backend.write_calls.should contain("B")
      backend.move_calls.should be_empty # Optimization: cursor already at right position
    end

    it "calls backend.flush after rendering" do
      backend = MockBufferBackend.new
      buffer = Termisu::Buffer.new(5, 3)

      buffer.flush(backend)
      backend.flush_count.should eq(1)
    end

    it "renders colors for changed cells" do
      backend = MockBufferBackend.new
      buffer = Termisu::Buffer.new(5, 3)

      buffer.set_cell(2, 1, 'X', fg: Termisu::Color.yellow, bg: Termisu::Color.magenta)
      buffer.flush(backend)

      backend.fg_calls.should contain(Termisu::Color.yellow)
      backend.bg_calls.should contain(Termisu::Color.magenta)
    end

    it "renders attributes for changed cells" do
      backend = MockBufferBackend.new
      buffer = Termisu::Buffer.new(5, 3)

      buffer.set_cell(2, 1, 'B', attr: Termisu::Attribute::Bold)
      buffer.flush(backend)

      backend.bold_count.should be > 0
      # Note: Optimized rendering doesn't reset after each cell,
      # only when attributes are removed in a subsequent cell
    end

    it "batches consecutive cells with same styling" do
      backend = MockBufferBackend.new
      buffer = Termisu::Buffer.new(10, 3)

      # Set 3 consecutive cells with same styling
      buffer.set_cell(2, 1, 'A', fg: Termisu::Color.green)
      buffer.set_cell(3, 1, 'B', fg: Termisu::Color.green)
      buffer.set_cell(4, 1, 'C', fg: Termisu::Color.green)
      buffer.flush(backend)

      # Clear and set up for diff test
      backend.write_calls.clear
      backend.move_calls.clear
      backend.fg_calls.clear

      # Change same cells again
      buffer.set_cell(2, 1, 'X', fg: Termisu::Color.red)
      buffer.set_cell(3, 1, 'Y', fg: Termisu::Color.red)
      buffer.set_cell(4, 1, 'Z', fg: Termisu::Color.red)
      buffer.flush(backend)

      # Should batch into single write "XYZ"
      backend.write_calls.should contain("XYZ")
      # Should only set color once (not 3 times)
      backend.fg_calls.size.should eq(1)
      backend.fg_calls[0].should eq(Termisu::Color.red)
    end

    it "splits batches when styling changes" do
      backend = MockBufferBackend.new
      buffer = Termisu::Buffer.new(10, 3)

      # Set cells with different colors
      buffer.set_cell(2, 1, 'A', fg: Termisu::Color.green)
      buffer.set_cell(3, 1, 'B', fg: Termisu::Color.red) # Different color
      buffer.set_cell(4, 1, 'C', fg: Termisu::Color.red) # Same as B
      buffer.flush(backend)

      # Should have separate writes for different styles
      backend.write_calls.should contain("A")
      backend.write_calls.should contain("BC")
    end
  end

  describe "#sync (full redraw)" do
    it "renders all cells regardless of changes" do
      backend = MockBufferBackend.new
      buffer = Termisu::Buffer.new(3, 2)

      # Set one cell
      buffer.set_cell(1, 1, 'A')

      # First flush
      buffer.flush(backend)

      # Clear tracking
      backend.write_calls.clear

      # Sync should render all 6 cells (3x2)
      # With batching, cells with same style are batched together
      buffer.sync(backend)

      # Total characters rendered should equal total cells
      total_chars = backend.write_calls.sum(&.size)
      total_chars.should eq(6)
      backend.flush_count.should eq(2) # flush + sync
    end

    it "batches cells with same styling on sync" do
      backend = MockBufferBackend.new
      buffer = Termisu::Buffer.new(5, 1)

      # All default cells - should batch into single write
      buffer.sync(backend)

      # All 5 cells should be in a single batched write
      backend.write_calls.size.should eq(1)
      backend.write_calls[0].size.should eq(5)
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
end
