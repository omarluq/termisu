# Buffer manages a 2D grid of cells with double buffering support.
#
# Buffer maintains:
# - Front buffer: What's currently displayed on screen
# - Back buffer: Where new content is written
# - Diff algorithm: Only redraws cells that have changed
# - Render state tracking for escape sequence optimization
#
# Performance Optimizations:
# - Only emits color/attribute escape sequences when they change
# - Batches consecutive cells on the same row with the same styling
# - Tracks dirty rows to skip unnecessary render work
#
# Example:
# ```
# buffer = Termisu::Buffer.new(80, 24)
# buffer.set_cell(10, 5, 'A', fg: Color.green, bg: Color.black)
# buffer.render_to(renderer) # Only changed cells are redrawn
# ```
class Termisu::Buffer
  Log = Termisu::Logs::Buffer
  getter width : Int32
  getter height : Int32

  @front : Array(Cell)                   # Currently displayed buffer
  @back : Array(Cell)                    # Buffer being written to
  @render_state : RenderState            # Tracks current terminal state for optimization
  @batch_buffer : IO::Memory             # Reusable buffer for character batching
  @row_non_default_counts : Array(Int32) # Number of non-default cells per back-buffer row
  @dirty_rows : Array(Bool)              # Rows that may differ between front/back
  @dirty_row_list : Array(Int32)         # Ordered list of currently dirty row indices
  @any_dirty : Bool                      # Fast-path flag for dirty row checks

  # Creates a new Buffer with the specified dimensions.
  #
  # Parameters:
  # - width: Number of columns
  # - height: Number of rows
  def initialize(@width : Int32, @height : Int32)
    size = @width * @height
    @front = Array(Cell).new(size, Cell.default)
    @back = Array(Cell).new(size, Cell.default)
    @render_state = RenderState.new
    @batch_buffer = IO::Memory.new(@width) # Pre-sized for typical row batches
    @row_non_default_counts = Array(Int32).new(@height, 0)
    @dirty_rows = Array(Bool).new(@height, false)
    @dirty_row_list = [] of Int32
    @any_dirty = false
    Log.debug { "Buffer initialized: #{@width}x#{@height} (#{size} cells)" }
  end

  # Sets a cell at the specified position in the back buffer.
  #
  # Parameters:
  # - x: Column position (0-based)
  # - y: Row position (0-based)
  # - grapheme: Character to display
  # - fg: Foreground color (default: white)
  # - bg: Background color (default: default terminal color)
  # - attr: Text attributes (default: None)
  #
  # Returns false if coordinates are out of bounds, the character is a
  # non-printable control character (C0/C1 controls except space), the
  # character is wide and cannot fit (width 2 at last column), or the
  # character has display width 0 (standalone combining marks).
  def set_cell(
    x : Int32,
    y : Int32,
    grapheme : String,
    fg : Color = Color.white,
    bg : Color = Color.default,
    attr : Attribute = Attribute::None,
  ) : Bool
    return false if out_of_bounds?(x, y)
    return false unless grapheme.grapheme_size == 1
    return false if control_char?(grapheme[0])

    # Create cell to determine width
    cell = Cell.new(grapheme, fg: fg, bg: bg, attr: attr)
    width = cell.width

    # Reject wide writes that cannot fit
    return false if width == 2 && x >= @width - 1

    # Enforce width-0 policy: standalone width-0 characters (combining marks)
    # are rejected so the Char API never consumes a logical grid cell without
    # consuming columns. This prevents rendering anomalies where invisible
    # characters would occupy buffer cells without visible content.
    return false if width == 0

    set_cell_internal(x, y, cell, width)
    true
  end

  def set_cell(
    x : Int32,
    y : Int32,
    ch : Char,
    fg : Color = Color.white,
    bg : Color = Color.default,
    attr : Attribute = Attribute::None,
  ) : Bool
    set_cell(x, y, ch.to_s, fg, bg, attr)
  end

  # Internal cell writer that handles occupancy invariants and overlap clearing.
  #
  # This is the core write primitive that handles:
  # - Wide character writes (creates leading + continuation cells)
  # - Overlap clearing when overwriting wide cells or their continuations
  # - Pre-clearing target cells before writing
  #
  # Assumes caller has validated bounds and fit constraints.
  private def set_cell_internal(x : Int32, y : Int32, cell : Cell, width : UInt8) : Nil
    row_start = y * @width

    # Clear overlap: if writing into a continuation cell, clear its owner first
    if @back[row_start + x].continuation?
      clear_continuation_owner(x, y)
    end

    # Clear overlap: if overwriting a wide cell, clear its continuation
    if width == 2
      # If x+1 is a wide leading cell, clear its continuation at x+2 first
      # to prevent orphan continuation cells (BUG-008)
      if x + 2 < @width && @back[row_start + x + 1].width == 2
        assign_back_cell(row_start + x + 2, y, Cell.default)
      end

      # Pre-clear both target positions
      assign_back_cell(row_start + x, y, Cell.default)
      assign_back_cell(row_start + x + 1, y, Cell.default)

      # Write leading cell
      assign_back_cell(row_start + x, y, cell)
      # Write continuation cell
      assign_back_cell(row_start + x + 1, y, Cell.continuation)
    else
      # Narrow write: clear any wide cell that overlaps next position
      if x + 1 < @width && @back[row_start + x].width == 2
        assign_back_cell(row_start + x + 1, y, Cell.default)
      end
      assign_back_cell(row_start + x, y, cell)
    end
  end

  # Clears the owner of a continuation cell.
  #
  # If the cell at (x, y) is a continuation cell, clears its leading cell
  # at (x-1, y) to prevent orphan continuation.
  private def clear_continuation_owner(x : Int32, y : Int32) : Nil
    return if x == 0

    row_start = y * @width
    return unless @back[row_start + x].continuation?

    assign_back_cell(row_start + x - 1, y, Cell.default)
  end

  # Gets a cell at the specified position from the back buffer.
  #
  # Returns nil if coordinates are out of bounds.
  def get_cell(x : Int32, y : Int32) : Cell?
    return if out_of_bounds?(x, y)

    idx = y * @width + x
    @back[idx]
  end

  # Clears the back buffer (fills with default cells).
  def clear
    @height.times do |row|
      # Skip rows that are already fully default.
      next if @row_non_default_counts[row] == 0

      row_start = row * @width
      row_end = row_start + @width
      idx = row_start
      while idx < row_end
        @back[idx] = Cell.default
        idx += 1
      end

      @row_non_default_counts[row] = 0
      mark_row_dirty(row)
    end
  end

  # Invalidates the front buffer, forcing a full re-render on next render_to.
  #
  # Call this after the terminal screen has been cleared externally
  # (e.g., re-entering alternate screen after a mode switch).
  # The next render_to will redraw all cells since none will match
  # the invalidated front buffer.
  #
  # Internal invariant exception: This method creates cells with NUL ('\u0000')
  # which have width 0 but continuation=false. This is intentional—the NUL sentinel
  # must never match any normal content, and normal content never passes through
  # set_cell's control_char? guard which would reject it.
  def invalidate
    # Fill front buffer with invalid marker cells that won't match any real content.
    # Using NUL character as the marker since it's never used in normal rendering.
    # Note: This intentionally creates width 0 non-continuation cells as sentinels.
    invalid_cell = Cell.new("\u0000", fg: Color.default, bg: Color.default, attr: Attribute::None)
    @front.size.times do |index|
      @front[index] = invalid_cell
    end
    @render_state.reset
    mark_all_rows_dirty
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
  # - auto_flush: Whether to flush at the end (default: true). Set to false
  #   when caller needs to control flush timing (e.g., for synchronized updates).
  def render_to(renderer : Renderer, auto_flush : Bool = true)
    if @any_dirty
      @dirty_row_list.each do |row|
        render_row_diff(renderer, row)
        @dirty_rows[row] = false
      end
      @dirty_row_list.clear
      @any_dirty = false
    end

    renderer.flush if auto_flush
  end

  # Forces a full redraw of all cells to the renderer, ignoring the diff.
  #
  # Useful after terminal resize or corruption.
  #
  # Parameters:
  # - renderer: The renderer to render cells to
  # - auto_flush: Whether to flush at the end (default: true). Set to false
  #   when caller needs to control flush timing (e.g., for synchronized updates).
  def sync_to(renderer : Renderer, auto_flush : Bool = true)
    # Reset render state to force all sequences to be emitted
    @render_state.reset

    @height.times do |row|
      render_row_full(renderer, row)
    end

    reset_dirty_rows

    renderer.flush if auto_flush
  end

  # Resizes the buffer to new dimensions.
  #
  # Preserves existing content where possible. New cells are default.
  # Ensures occupancy invariants are preserved (no orphan continuation cells).
  def resize(new_width : Int32, new_height : Int32)
    return if new_width == @width && new_height == @height

    new_size = new_width * new_height
    new_back = Array(Cell).new(new_size, Cell.default)
    new_front = Array(Cell).new(new_size, Cell.default)

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

      # Fix occupancy invariants in new buffer:
      # - Wide cells at last column cannot have continuation -> replace with default
      # - Orphan continuation cells -> replace with default
      row_start = row * new_width
      new_width.times do |col|
        idx = row_start + col

        # Wide cell at last column is invalid
        if col == new_width - 1 && new_back[idx].width == 2
          new_back[idx] = Cell.default
          new_front[idx] = Cell.default
          next
        end

        # Orphan continuation (no leading cell) -> replace with default
        if new_back[idx].continuation?
          if col == 0 || new_back[idx - 1].width != 2
            new_back[idx] = Cell.default
            new_front[idx] = Cell.default
          end
        end
      end
    end

    @width = new_width
    @height = new_height
    @back = new_back
    @front = new_front
    rebuild_row_non_default_counts
    @dirty_rows = Array(Bool).new(@height, true)
    @dirty_row_list = Array(Int32).new(@height) { |row| row }
    @any_dirty = @height > 0
  end

  # Checks if coordinates are within buffer bounds.
  private def out_of_bounds?(x : Int32, y : Int32) : Bool
    x < 0 || x >= @width || y < 0 || y >= @height
  end

  # Rejects C0 controls (0x00-0x1F except space) and C1 controls (0x7F-0x9F).
  # These characters would desync render-state cursor tracking because
  # the terminal interprets them as movement commands, not display characters.
  private def control_char?(char : Char) : Bool
    cp = char.ord
    cp < 0x20 || (cp >= 0x7F && cp <= 0x9F)
  end

  # Assigns a cell in the back buffer while maintaining:
  # - non-default row counts (for selective clear)
  # - dirty row tracking (for selective render diff)
  private def assign_back_cell(index : Int32, row : Int32, new_cell : Cell) : Nil
    old_cell = @back[index]
    return if old_cell == new_cell

    old_default = old_cell.default_state?
    new_default = new_cell.default_state?
    if old_default != new_default
      @row_non_default_counts[row] += new_default ? -1 : 1
    end

    @back[index] = new_cell
    mark_row_dirty(row)
  end

  private def mark_row_dirty(row : Int32) : Nil
    return if @dirty_rows[row]
    @dirty_rows[row] = true
    @dirty_row_list << row
    @any_dirty = true
  end

  private def mark_all_rows_dirty : Nil
    @dirty_rows.fill(true)
    @dirty_row_list.clear
    @height.times { |row| @dirty_row_list << row }
    @any_dirty = @height > 0
  end

  private def reset_dirty_rows : Nil
    @dirty_rows.fill(false)
    @dirty_row_list.clear
    @any_dirty = false
  end

  private def rebuild_row_non_default_counts : Nil
    counts = Array(Int32).new(@height, 0)

    @height.times do |row|
      row_start = row * @width
      row_end = row_start + @width
      idx = row_start
      count = 0

      while idx < row_end
        count += 1 unless @back[idx].default_state?
        idx += 1
      end

      counts[row] = count
    end

    @row_non_default_counts = counts
  end

  # Renders a row using diff-based rendering (only changed cells).
  #
  # Batches consecutive changed cells with same styling for efficiency.
  # Continuation cells (trailing cells of wide graphemes) are skipped during
  # rendering since they're never drawn directly. Updates front buffer to
  # match back buffer after rendering.
  private def render_row_diff(renderer : Renderer, row : Int32)
    render_row(renderer, row, diff_only: true)
  end

  # Renders an entire row (for sync/full redraw).
  #
  # Batches consecutive cells with same styling for efficiency.
  # Continuation cells (trailing cells of wide graphemes) are skipped during
  # rendering since they're never drawn directly. Updates front buffer to
  # match back buffer after rendering.
  private def render_row_full(renderer : Renderer, row : Int32)
    render_row(renderer, row, diff_only: false)
  end

  private def render_row(renderer : Renderer, row : Int32, *, diff_only : Bool)
    row_start = row * @width
    col = 0

    while col < @width
      idx = row_start + col
      back_cell = @back[idx]
      front_cell = @front[idx]

      if skip_row_cell?(back_cell, front_cell, idx, diff_only)
        col += 1
        next
      end

      # Start a batch with current cell's styling
      col = render_row_batch(renderer, row, row_start, col, back_cell, diff_only)
    end
  end

  private def skip_row_cell?(back_cell : Cell, front_cell : Cell, idx : Int32, diff_only : Bool) : Bool
    return true if diff_only && back_cell == front_cell

    return false unless back_cell.continuation?

    @front[idx] = back_cell
    true
  end

  private def render_row_batch(
    renderer : Renderer,
    row : Int32,
    row_start : Int32,
    col : Int32,
    first_cell : Cell,
    diff_only : Bool,
  ) : Int32
    batch_start = col
    batch_fg = first_cell.fg
    batch_bg = first_cell.bg
    batch_attr = first_cell.attr

    @batch_buffer.clear
    columns_advanced = 0

    while col < @width
      idx = row_start + col
      back_cell = @back[idx]
      front_cell = @front[idx]

      break if diff_only && back_cell == front_cell

      if back_cell.continuation?
        @front[idx] = back_cell
        col += 1
        next
      end

      break if back_cell.fg != batch_fg || back_cell.bg != batch_bg || back_cell.attr != batch_attr

      @batch_buffer << back_cell.grapheme
      columns_advanced += back_cell.width
      @front[idx] = back_cell
      col += 1
    end

    render_batch(renderer, batch_start, row, @batch_buffer.to_s, batch_fg, batch_bg, batch_attr, columns_advanced)
    col
  end

  # Renders a batch of characters with the same styling.
  #
  # Uses RenderState to minimize escape sequence emission:
  # - Only moves cursor if not at expected position
  # - Only emits color/attribute sequences when they change
  #
  # Cursor advancement is based on cell widths (columns_advanced), not
  # codepoint count. This keeps render-state cursor tracking in sync with
  # the terminal's actual cursor position when rendering wide characters.
  private def render_batch(
    renderer : Renderer,
    x : Int32,
    y : Int32,
    chars : String,
    fg : Color,
    bg : Color,
    attr : Attribute,
    columns_advanced : Int32,
  )
    return if chars.empty?

    renderer.move_cursor(x, y)

    # Apply style only if changed
    @render_state.apply_style(renderer, fg, bg, attr)

    renderer.write(chars, columns_advanced)
  end
end
