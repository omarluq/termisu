# Buffer manages a 2D grid of cells with double buffering support.
#
# Buffer maintains:
# - Front buffer: What's currently displayed on screen
# - Back buffer: Where new content is written
# - Diff algorithm: Only redraws cells that have changed
# - Cursor position and visibility
# - Render state tracking for escape sequence optimization
#
# Performance Optimizations:
# - Only emits color/attribute escape sequences when they change
# - Batches consecutive cells on the same row with the same styling
# - Tracks cursor position to minimize move_cursor calls
#
# Example:
# ```
# buffer = Termisu::Buffer.new(80, 24)
# buffer.set_cell(10, 5, 'A', fg: Color.green, bg: Color.black)
# buffer.set_cursor(10, 5)
# buffer.render_to(renderer) # Only changed cells and cursor are redrawn
# ```
class Termisu::Buffer
  getter width : Int32
  getter height : Int32
  getter cursor : Cursor

  @front : Array(Cell)        # Currently displayed buffer
  @back : Array(Cell)         # Buffer being written to
  @render_state : RenderState # Tracks current terminal state for optimization

  # Creates a new Buffer with the specified dimensions.
  #
  # Parameters:
  # - width: Number of columns
  # - height: Number of rows
  def initialize(@width : Int32, @height : Int32)
    size = @width * @height
    @front = Array(Cell).new(size) { Cell.default }
    @back = Array(Cell).new(size) { Cell.default }
    @cursor = Cursor.new # Hidden by default
    @render_state = RenderState.new
  end

  # Sets a cell at the specified position in the back buffer.
  #
  # Parameters:
  # - x: Column position (0-based)
  # - y: Row position (0-based)
  # - ch: Character to display
  # - fg: Foreground color (default: white)
  # - bg: Background color (default: default terminal color)
  # - attr: Text attributes (default: None)
  #
  # Returns false if coordinates are out of bounds.
  def set_cell(
    x : Int32,
    y : Int32,
    ch : Char,
    fg : Color = Color.white,
    bg : Color = Color.default,
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

  # Sets cursor position and makes it visible.
  #
  # Coordinates are clamped to buffer bounds. Negative values are clamped to 0.
  # Values exceeding buffer dimensions are clamped to max valid position.
  def set_cursor(x : Int32, y : Int32)
    clamped_x = x.clamp(0, @width - 1)
    clamped_y = y.clamp(0, @height - 1)
    @cursor.set_position(clamped_x, clamped_y)
  end

  # Hides the cursor.
  def hide_cursor
    @cursor.hide
  end

  # Shows the cursor at current position (or 0,0 if never positioned).
  def show_cursor
    @cursor.show
  end

  # Renders changes to the renderer by diffing front and back buffers.
  #
  # Only cells that have changed are redrawn. After rendering,
  # the back buffer becomes the new front buffer.
  # Cursor position and visibility are also updated.
  #
  # Optimizations applied:
  # - Batches consecutive cells with same styling on same row
  # - Only emits escape sequences when color/attribute changes
  # - Minimizes cursor movement by tracking position
  #
  # Parameters:
  # - renderer: The renderer to render cells to
  def render_to(renderer : Renderer)
    @height.times do |row|
      render_row_diff(backend, row)
      @width.times do |col|
        idx = row * @width + col
        front_cell = @front[idx]
        back_cell = @back[idx]

        # Only redraw if cell has changed
        if front_cell != back_cell
          render_cell(renderer, col, row, back_cell)
          @front[idx] = back_cell
        end
      end
    end

    # Render cursor
    render_cursor(renderer)

    renderer.flush
  end

  # Forces a full redraw of all cells to the renderer, ignoring the diff.
  #
  # Useful after terminal resize or corruption.
  def sync(backend : Backend)
    # Reset render state to force all sequences to be emitted
    @render_state.reset

    @height.times do |row|
      render_row_full(backend, row)
  def sync_to(renderer : Renderer)
    @height.times do |row|
      @width.times do |col|
        idx = row * @width + col
        back_cell = @back[idx]
        render_cell(renderer, col, row, back_cell)
        @front[idx] = back_cell
      end
    end

    # Render cursor
    render_cursor(renderer)

    renderer.flush
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

    # Clamp cursor position to new bounds
    @cursor.clamp(@width, @height)
  end

  # Checks if coordinates are within buffer bounds.
  private def out_of_bounds?(x : Int32, y : Int32) : Bool
    x < 0 || x >= @width || y < 0 || y >= @height
  end

  # Renders a single cell to the renderer.
  private def render_cell(renderer : Renderer, x : Int32, y : Int32, cell : Cell)
    renderer.move_cursor(x, y)

    # Set colors explicitly for each cell
    renderer.foreground = cell.fg
    renderer.background = cell.bg

    # Apply attributes
    apply_attributes(renderer, cell.attr)

    # Write character
    renderer.write(cell.ch.to_s)

    # Reset after writing if attributes were used
    if cell.attr != Attribute::None
      renderer.reset_attributes
      # Restore default colors after reset
      renderer.foreground = Color.white
      renderer.background = Color.default
    end
  end

  # Applies cell attributes to the renderer.
  private def apply_attributes(renderer : Renderer, attr : Attribute)
    renderer.enable_bold if attr.bold?
    renderer.enable_underline if attr.underline?
    renderer.enable_reverse if attr.reverse?
    renderer.enable_blink if attr.blink?
    # Dim, Cursive, Hidden not yet supported in renderer
  end

  # Renders cursor position and visibility to the renderer.
  private def render_cursor(renderer : Renderer)
    if @cursor.visible?
      renderer.move_cursor(@cursor.x, @cursor.y)
      renderer.write_show_cursor
    else
      renderer.write_hide_cursor
    end
  end

  # Renders a row using diff-based rendering (only changed cells).
  #
  # Batches consecutive changed cells with same styling for efficiency.
  # Updates front buffer to match back buffer after rendering.
  private def render_row_diff(backend : Backend, row : Int32)
    row_start = row * @width
    col = 0

    while col < @width
      idx = row_start + col
      back_cell = @back[idx]
      front_cell = @front[idx]

      # Skip unchanged cells
      if back_cell == front_cell
        col += 1
        next
      end

      # Found a changed cell - start a batch
      batch_start = col
      batch_fg = back_cell.fg
      batch_bg = back_cell.bg
      batch_attr = back_cell.attr

      # Collect consecutive changed cells with same styling
      batch_chars = String.build do |str|
        while col < @width
          idx = row_start + col
          back_cell = @back[idx]
          front_cell = @front[idx]

          # Stop if unchanged or different styling
          break if back_cell == front_cell
          break if back_cell.fg != batch_fg || back_cell.bg != batch_bg || back_cell.attr != batch_attr

          str << back_cell.ch
          @front[idx] = back_cell # Update front buffer
          col += 1
        end
      end

      # Render the batch
      render_batch(backend, batch_start, row, batch_chars, batch_fg, batch_bg, batch_attr)
    end
  end

  # Renders an entire row (for sync/full redraw).
  #
  # Batches consecutive cells with same styling for efficiency.
  # Updates front buffer to match back buffer after rendering.
  private def render_row_full(backend : Backend, row : Int32)
    row_start = row * @width
    col = 0

    while col < @width
      idx = row_start + col
      cell = @back[idx]

      # Start a batch with current cell's styling
      batch_start = col
      batch_fg = cell.fg
      batch_bg = cell.bg
      batch_attr = cell.attr

      # Collect consecutive cells with same styling
      batch_chars = String.build do |str|
        while col < @width
          idx = row_start + col
          cell = @back[idx]

          # Stop if different styling
          break if cell.fg != batch_fg || cell.bg != batch_bg || cell.attr != batch_attr

          str << cell.ch
          @front[idx] = cell # Update front buffer
          col += 1
        end
      end

      # Render the batch
      render_batch(backend, batch_start, row, batch_chars, batch_fg, batch_bg, batch_attr)
    end
  end

  # Renders a batch of characters with the same styling.
  #
  # Uses RenderState to minimize escape sequence emission:
  # - Only moves cursor if not at expected position
  # - Only emits color/attribute sequences when they change
  private def render_batch(
    backend : Backend,
    x : Int32,
    y : Int32,
    chars : String,
    fg : Color,
    bg : Color,
    attr : Attribute,
  )
    return if chars.empty?

    # Move cursor only if needed
    @render_state.move_cursor(backend, x, y)

    # Apply style only if changed
    @render_state.apply_style(backend, fg, bg, attr)

    # Write all characters in the batch
    backend.write(chars)

    # Update cursor position in render state (cursor advances with each char)
    chars.each_char do
      @render_state.advance_cursor
    end
  end
end
