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
# - Tracks per-row damage ranges to bound diff scans to changed column spans
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

  # Cells are stored structure-of-arrays as packed identity keys (see
  # Cell#key). The diff scan and write dedup compare bare UInt128s and never
  # dereference String memory. The grapheme plane holds the String only for
  # interned (non-ASCII) graphemes — ASCII graphemes are decoded from the key
  # itself — and is written only when such a cell is drawn. The front buffer
  # is keys-only: it exists purely for diffing, never for content lookup.
  @front_keys : Array(UInt128)           # Keys currently displayed on screen
  @back_keys : Array(UInt128)            # Keys being written to
  @graphemes : Array(String)             # Back-buffer plane for interned graphemes
  @render_state : RenderState            # Tracks current terminal state for optimization
  @batch_buffer : IO::Memory             # Reusable buffer for character batching
  @row_non_default_counts : Array(Int32) # Number of non-default cells per back-buffer row
  @dirty_rows : Array(Bool)              # Rows that may differ between front/back
  @dirty_row_list : Array(Int32)         # Ordered list of currently dirty row indices
  @any_dirty : Bool                      # Fast-path flag for dirty row checks

  # Per-row damage range, stored as flat buffer indices: for a dirty row,
  # every cell where back and front may differ lies within
  # dirty_min_idx..dirty_max_idx. Clean rows hold the empty-range sentinels
  # (min = Int32::MAX, max = -1). The invariant holds because every
  # back-buffer mutation flows through assign_back_key (which extends the
  # range, including wide-cell continuation writes and overlap clears),
  # except clear/resize/invalidate which mark full-row ranges.
  @dirty_min_idx : Array(Int32)
  @dirty_max_idx : Array(Int32)

  # Front-buffer sentinel used by invalidate: a NUL cell key that no back
  # buffer key can ever equal (see invalidate's invariant note).
  private INVALID_KEY = Cell.new("\u0000", fg: Color.default, bg: Color.default, attr: Attribute::None).key

  # Creates a new Buffer with the specified dimensions.
  #
  # Parameters:
  # - width: Number of columns
  # - height: Number of rows
  def initialize(@width : Int32, @height : Int32)
    size = @width * @height
    @front_keys = Array(UInt128).new(size, Cell::DEFAULT_KEY)
    @back_keys = Array(UInt128).new(size, Cell::DEFAULT_KEY)
    @graphemes = Array(String).new(size, "")
    @render_state = RenderState.new
    @batch_buffer = IO::Memory.new(@width) # Pre-sized for typical row batches
    @row_non_default_counts = Array(Int32).new(@height, 0)
    @dirty_rows = Array(Bool).new(@height, false)
    @dirty_row_list = [] of Int32
    @any_dirty = false
    @dirty_min_idx = Array(Int32).new(@height, Int32::MAX)
    @dirty_max_idx = Array(Int32).new(@height, -1)
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
    return false unless single_grapheme?(grapheme)
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

  # Interned single-character strings for ASCII, avoiding one Char#to_s heap
  # allocation per set_cell(Char) call. Control-char entries are harmless:
  # they are rejected downstream by control_char?, identical to ch.to_s.
  private ASCII_GRAPHEMES = Array(String).new(128, &.unsafe_chr.to_s)

  def set_cell(
    x : Int32,
    y : Int32,
    ch : Char,
    fg : Color = Color.white,
    bg : Color = Color.default,
    attr : Attribute = Attribute::None,
  ) : Bool
    # ch.ascii? proves ch.ord is in 0..127, so unsafe_fetch is in bounds.
    grapheme = ch.ascii? ? ASCII_GRAPHEMES.unsafe_fetch(ch.ord) : ch.to_s
    set_cell(x, y, grapheme, fg, bg, attr)
  end

  # Internal cell writer that handles occupancy invariants and overlap clearing.
  #
  # This is the core write primitive that handles:
  # - Wide character writes (creates leading + continuation cells)
  # - Overlap clearing when overwriting wide cells or their continuations
  # - Direct overwrite of target cells (assign_back_key handles count/dirty
  #   deltas per transition)
  #
  # Assumes caller has validated bounds and fit constraints.
  private def set_cell_internal(x : Int32, y : Int32, cell : Cell, width : UInt8) : Nil
    row_start = y * @width

    # Clear overlap: if writing into a continuation cell, clear its owner first
    if Cell.key_continuation?(@back_keys[row_start + x])
      clear_continuation_owner(x, y)
    end

    # Clear overlap: if overwriting a wide cell, clear its continuation
    if width == 2
      # If x+1 is a wide leading cell, clear its continuation at x+2 first
      # to prevent orphan continuation cells (BUG-008)
      if x + 2 < @width && Cell.key_width(@back_keys[row_start + x + 1]) == 2
        assign_back_key(row_start + x + 2, y, Cell::DEFAULT_KEY, "")
      end

      # Overwrite targets directly: assign_back_key count/dirty updates depend
      # only on old/new endpoints, so no pre-clear is needed; a rewrite of an
      # identical wide cell is a no-op and leaves the row clean.
      # Write leading cell
      assign_back_key(row_start + x, y, cell.key, cell.grapheme)
      # Write continuation cell
      assign_back_key(row_start + x + 1, y, Cell::CONTINUATION_KEY, "")
    else
      # Narrow write: clear any wide cell that overlaps next position
      if x + 1 < @width && Cell.key_width(@back_keys[row_start + x]) == 2
        assign_back_key(row_start + x + 1, y, Cell::DEFAULT_KEY, "")
      end
      assign_back_key(row_start + x, y, cell.key, cell.grapheme)
    end
  end

  # Clears the owner of a continuation cell.
  #
  # If the cell at (x, y) is a continuation cell, clears its leading cell
  # at (x-1, y) to prevent orphan continuation.
  private def clear_continuation_owner(x : Int32, y : Int32) : Nil
    return if x == 0

    row_start = y * @width
    return unless Cell.key_continuation?(@back_keys[row_start + x])

    assign_back_key(row_start + x - 1, y, Cell::DEFAULT_KEY, "")
  end

  # Gets a cell at the specified position from the back buffer.
  #
  # Returns nil if coordinates are out of bounds.
  #
  # The Cell is reconstructed from the packed key and grapheme plane (cold
  # path); it compares equal to the cell originally written.
  def get_cell(x : Int32, y : Int32) : Cell?
    return if out_of_bounds?(x, y)

    idx = y * @width + x
    key = @back_keys[idx]
    Cell.from_key(key, grapheme_for(idx, key))
  end

  # Clears the back buffer (fills with default cells).
  def clear
    @height.times do |row|
      # Skip rows that are already fully default.
      next if @row_non_default_counts[row] == 0

      row_start = row * @width
      @back_keys.fill(Cell::DEFAULT_KEY, row_start, @width)

      @row_non_default_counts[row] = 0
      mark_row_damaged_fully(row)
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
    # Fill front buffer with invalid marker keys that won't match any real content.
    # Using NUL character as the marker since it's never used in normal rendering.
    # Note: This intentionally uses a width 0 non-continuation key as sentinel.
    @front_keys.fill(INVALID_KEY)
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
        @dirty_min_idx[row] = Int32::MAX
        @dirty_max_idx[row] = -1
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
    new_back = Array(UInt128).new(new_size, Cell::DEFAULT_KEY)
    new_front = Array(UInt128).new(new_size, Cell::DEFAULT_KEY)
    new_graphemes = Array(String).new(new_size, "")

    # Copy existing content (up to new dimensions)
    min_height = Math.min(@height, new_height)
    min_width = Math.min(@width, new_width)

    min_height.times do |row|
      min_width.times do |col|
        old_idx = row * @width + col
        new_idx = row * new_width + col
        new_back[new_idx] = @back_keys[old_idx]
        new_front[new_idx] = @front_keys[old_idx]
        new_graphemes[new_idx] = @graphemes[old_idx]
      end

      # Fix occupancy invariants in new buffer:
      # - Wide cells at last column cannot have continuation -> replace with default
      # - Orphan continuation cells -> replace with default
      row_start = row * new_width
      new_width.times do |col|
        idx = row_start + col

        # Wide cell at last column is invalid
        if col == new_width - 1 && Cell.key_width(new_back[idx]) == 2
          new_back[idx] = Cell::DEFAULT_KEY
          new_front[idx] = Cell::DEFAULT_KEY
          next
        end

        # Orphan continuation (no leading cell) -> replace with default
        if Cell.key_continuation?(new_back[idx])
          if col == 0 || Cell.key_width(new_back[idx - 1]) != 2
            new_back[idx] = Cell::DEFAULT_KEY
            new_front[idx] = Cell::DEFAULT_KEY
          end
        end
      end
    end

    @width = new_width
    @height = new_height
    @back_keys = new_back
    @front_keys = new_front
    @graphemes = new_graphemes
    rebuild_row_non_default_counts
    @dirty_rows = Array(Bool).new(@height, true)
    @dirty_row_list = Array(Int32).new(@height) { |row| row }
    @any_dirty = @height > 0
    @dirty_min_idx = Array(Int32).new(@height) { |row| row * @width }
    @dirty_max_idx = Array(Int32).new(@height) { |row| row * @width + @width - 1 }
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

  # Fast path: a single ASCII byte is always exactly one grapheme cluster,
  # so skip the full segmentation walk (Char::Reader + property binary
  # searches) that String#grapheme_size performs even for 1-char strings.
  # Single bytes >= 0x80 (invalid UTF-8) intentionally fall through to
  # grapheme_size to preserve existing replacement-character acceptance.
  private def single_grapheme?(grapheme : String) : Bool
    return true if grapheme.bytesize == 1 && grapheme.to_unsafe[0] < 0x80
    grapheme.grapheme_size == 1
  end

  # Assigns a cell key in the back buffer while maintaining:
  # - non-default row counts (for selective clear)
  # - dirty row tracking (for selective render diff)
  # - per-row damage ranges (for bounded diff scans)
  #
  # The grapheme is stored in the plane only when the key says it is interned
  # (non-ASCII); callers writing ASCII-decodable keys (default, continuation)
  # pass "" which is never read back.
  private def assign_back_key(index : Int32, row : Int32, new_key : UInt128, grapheme : String) : Nil
    old_key = @back_keys[index]
    return if old_key == new_key

    old_default = old_key == Cell::DEFAULT_KEY
    new_default = new_key == Cell::DEFAULT_KEY
    if old_default != new_default
      @row_non_default_counts[row] += new_default ? -1 : 1
    end

    @back_keys[index] = new_key
    # unsafe bounds: index is bounds-validated by callers, @graphemes is sized
    # like @back_keys.
    @graphemes.unsafe_put(index, grapheme) if Cell.key_grapheme_interned?(new_key)

    # unsafe bounds: row is always height-validated by callers (see the
    # bounds-safety note on render_row); both arrays are sized @height.
    @dirty_min_idx.unsafe_put(row, index) if index < @dirty_min_idx.unsafe_fetch(row)
    @dirty_max_idx.unsafe_put(row, index) if index > @dirty_max_idx.unsafe_fetch(row)
    mark_row_dirty(row)
  end

  # Resolves the grapheme String for a back-buffer cell: interned (non-ASCII)
  # graphemes read the plane, everything else decodes from the key alone
  # (grapheme id is the ASCII byte). Continuation ids (0) only reach this via
  # get_cell, where Cell's constructor normalizes the grapheme to "".
  private def grapheme_for(idx : Int32, key : UInt128) : String
    if Cell.key_grapheme_interned?(key)
      @graphemes.unsafe_fetch(idx)
    else
      ASCII_GRAPHEMES.unsafe_fetch(Cell.key_grapheme_id(key))
    end
  end

  private def mark_row_dirty(row : Int32) : Nil
    return if @dirty_rows[row]
    @dirty_rows[row] = true
    @dirty_row_list << row
    @any_dirty = true
  end

  # Marks a row dirty with a full-row damage range. Used when changed cells
  # are unknown (bulk fills, front-buffer invalidation).
  private def mark_row_damaged_fully(row : Int32) : Nil
    row_start = row * @width
    @dirty_min_idx[row] = row_start
    @dirty_max_idx[row] = row_start + @width - 1
    mark_row_dirty(row)
  end

  private def mark_all_rows_dirty : Nil
    @dirty_rows.fill(true)
    @dirty_row_list.clear
    @height.times do |row|
      @dirty_row_list << row
      row_start = row * @width
      @dirty_min_idx[row] = row_start
      @dirty_max_idx[row] = row_start + @width - 1
    end
    @any_dirty = @height > 0
  end

  private def reset_dirty_rows : Nil
    @dirty_rows.fill(false)
    @dirty_row_list.clear
    @any_dirty = false
    @dirty_min_idx.fill(Int32::MAX)
    @dirty_max_idx.fill(-1)
  end

  private def rebuild_row_non_default_counts : Nil
    counts = Array(Int32).new(@height, 0)

    @height.times do |row|
      row_start = row * @width
      row_end = row_start + @width
      idx = row_start
      count = 0

      while idx < row_end
        count += 1 unless @back_keys[idx] == Cell::DEFAULT_KEY
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

  # Bounds safety for unsafe_fetch/unsafe_put in render_row, skip_row_cell?,
  # and render_row_batch: idx = row * @width + col with col < @width (loop
  # guard: scan_end <= @width since dirty_max_idx entries are either -1
  # sentinels, validated in-row indices from assign_back_key, or
  # row_start + @width - 1 full-row marks; dirty_min_idx entries are
  # >= row_start by the same sources, and the sentinels yield an empty scan)
  # and row < @height (dirty_row_list entries and sync_to's height.times are
  # always height-validated); @front_keys/@back_keys/@graphemes are always
  # sized @width * @height (initialize/resize are the only array assignments).
  # Renderer callbacks must not mutate this buffer reentrantly. If resize is
  # ever made callable from a fiber other than the render fiber, or a
  # mark_row_dirty call site is added with an unvalidated row, revisit this.
  #
  # Diff scans are bounded to the row's damage range: outside it,
  # back == front by the damage-range invariant, so those cells cannot emit.
  # The scan compares packed keys only; grapheme Strings are dereferenced
  # solely for interned graphemes of cells actually emitted.
  private def render_row(renderer : Renderer, row : Int32, *, diff_only : Bool)
    row_start = row * @width

    if diff_only
      col = @dirty_min_idx[row] - row_start
      scan_end = @dirty_max_idx[row] + 1 - row_start
    else
      col = 0
      scan_end = @width
    end

    while col < scan_end
      idx = row_start + col
      back_key = @back_keys.unsafe_fetch(idx)

      if skip_row_cell?(back_key, idx, diff_only)
        col += 1
        next
      end

      # Start a batch with current cell's styling
      col = render_row_batch(renderer, row, row_start, col, back_key, diff_only)
    end
  end

  # bounds: see render_row (idx is a caller-validated in-bounds index)
  private def skip_row_cell?(back_key : UInt128, idx : Int32, diff_only : Bool) : Bool
    return true if diff_only && back_key == @front_keys.unsafe_fetch(idx)

    return false unless Cell.key_continuation?(back_key)

    @front_keys.unsafe_put(idx, back_key)
    true
  end

  private def render_row_batch(
    renderer : Renderer,
    row : Int32,
    row_start : Int32,
    col : Int32,
    first_key : UInt128,
    diff_only : Bool,
  ) : Int32
    batch_start = col
    batch_style = first_key & Cell::KEY_STYLE_MASK

    @batch_buffer.clear
    columns_advanced = 0

    while col < @width
      idx = row_start + col
      back_key = @back_keys.unsafe_fetch(idx)

      break if diff_only && back_key == @front_keys.unsafe_fetch(idx)

      if Cell.key_continuation?(back_key)
        @front_keys.unsafe_put(idx, back_key)
        col += 1
        next
      end

      break if (back_key & Cell::KEY_STYLE_MASK) != batch_style

      # ASCII graphemes are the key's grapheme-id byte; only interned
      # (non-ASCII) graphemes touch the String plane.
      gid = Cell.key_grapheme_id(back_key)
      if gid < 0x80
        @batch_buffer.write_byte(gid.to_u8!)
      else
        @batch_buffer << @graphemes.unsafe_fetch(idx)
      end
      columns_advanced += Cell.key_width(back_key)
      @front_keys.unsafe_put(idx, back_key)
      col += 1
    end

    render_batch(renderer, batch_start, row, @batch_buffer.to_slice,
      Cell.key_fg(first_key), Cell.key_bg(first_key), Cell.key_attr(first_key), columns_advanced)
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
  #
  # The batch content is passed as the scratch buffer's live slice (valid
  # until the next batch clears it); renderers consume it before returning.
  private def render_batch(
    renderer : Renderer,
    x : Int32,
    y : Int32,
    chars : Bytes,
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
