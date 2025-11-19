# Cell::Buffer manages a 2D grid of cells with double buffering support.
#
# Buffer maintains:
# - Front buffer: What's currently displayed on screen
# - Back buffer: Where new content is written
# - Diff algorithm: Only redraws cells that have changed
#
# Example:
# ```
# buffer = Termisu::Cell::Buffer.new(80, 24)
# buffer.set_cell(10, 5, 'A', fg: 2, bg: 0)
# buffer.flush(backend) # Only changed cells are redrawn
# ```
class Termisu::Cell::Buffer
  getter width : Int32
  getter height : Int32

  @front : Array(Cell) # Currently displayed buffer
  @back : Array(Cell)  # Buffer being written to

  # Creates a new Buffer with the specified dimensions.
  #
  # Parameters:
  # - width: Number of columns
  # - height: Number of rows
  def initialize(@width : Int32, @height : Int32)
    size = @width * @height
    @front = Array(Cell).new(size) { Cell.default }
    @back = Array(Cell).new(size) { Cell.default }
  end

  # Sets a cell at the specified position in the back buffer.
  #
  # Parameters:
  # - x: Column position (0-based)
  # - y: Row position (0-based)
  # - ch: Character to display
  # - fg: Foreground color (Color enum or Int32, default: White)
  # - bg: Background color (Color enum or Int32, default: Default/transparent)
  # - attr: Text attributes (default: None)
  #
  # Returns false if coordinates are out of bounds.
  def set_cell(
    x : Int32,
    y : Int32,
    ch : Char,
    fg : Color | Int32 = Color::White,
    bg : Color | Int32 = Color::Default,
    attr : Attribute = Attribute::None,
  ) : Bool
    return false if out_of_bounds?(x, y)

    idx = y * @width + x
    @back[idx] = Cell.new(ch, fg, bg, attr)
    true
  end

  # Gets a cell at the specified position from the back buffer.
  #
  # Returns nil if coordinates are out of bounds.
  def get_cell(x : Int32, y : Int32) : Cell?
    return nil if out_of_bounds?(x, y)

    idx = y * @width + x
    @back[idx]
  end

  # Clears the back buffer (fills with default cells).
  def clear
    @back.size.times do |index|
      @back[index] = Cell.default
    end
  end

  # Flushes changes to the backend by diffing front and back buffers.
  #
  # Only cells that have changed are redrawn. After flushing,
  # the back buffer becomes the new front buffer.
  #
  # Parameters:
  # - backend: The backend to render cells to
  def flush(backend : Backend)
    @height.times do |row|
      @width.times do |col|
        idx = row * @width + col
        front_cell = @front[idx]
        back_cell = @back[idx]

        # Only redraw if cell has changed
        if front_cell != back_cell
          render_cell(backend, col, row, back_cell)
          @front[idx] = back_cell
        end
      end
    end

    backend.flush
  end

  # Forces a full redraw of all cells, ignoring the diff.
  #
  # Useful after terminal resize or corruption.
  def sync(backend : Backend)
    @height.times do |row|
      @width.times do |col|
        idx = row * @width + col
        back_cell = @back[idx]
        render_cell(backend, col, row, back_cell)
        @front[idx] = back_cell
      end
    end

    backend.flush
  end

  # Resizes the buffer to new dimensions.
  #
  # Preserves existing content where possible. New cells are default.
  # Clears both front and back buffers after resize.
  def resize(new_width : Int32, new_height : Int32)
    return if new_width == @width && new_height == @height

    new_size = new_width * new_height
    new_back = Array(Cell).new(new_size) { Cell.default }
    new_front = Array(Cell).new(new_size) { Cell.default }

    # Copy existing content (up to new dimensions)
    min_height = Math.min(@height, new_height)
    min_width = Math.min(@width, new_width)

    min_height.times do |row|
      min_width.times do |col|
        old_idx = row * @width + col
        new_idx = row * new_width + col
        new_back[new_idx] = @back[old_idx]
        new_front[new_idx] = @front[old_idx]
      end
    end

    @width = new_width
    @height = new_height
    @back = new_back
    @front = new_front
  end

  # Checks if coordinates are within buffer bounds.
  private def out_of_bounds?(x : Int32, y : Int32) : Bool
    x < 0 || x >= @width || y < 0 || y >= @height
  end

  # Renders a single cell to the backend.
  private def render_cell(backend : Backend, x : Int32, y : Int32, cell : Cell)
    backend.move_cursor(x, y)

    # Set colors explicitly for each cell
    backend.foreground = cell.fg
    backend.background = cell.bg

    # Apply attributes
    apply_attributes(backend, cell.attr)

    # Write character
    backend.write(cell.ch.to_s)

    # Reset after writing if attributes were used
    if cell.attr != Attribute::None
      backend.reset_attributes
      # Restore default colors after reset
      backend.foreground = Color::White.value
      backend.background = Color::Default.value
    end
  end

  # Applies cell attributes to the backend.
  private def apply_attributes(backend : Backend, attr : Attribute)
    backend.enable_bold if attr.bold?
    backend.enable_underline if attr.underline?
    backend.enable_reverse if attr.reverse?
    backend.enable_blink if attr.blink?
    # Dim, Cursive, Hidden not yet supported in backend
  end
end
