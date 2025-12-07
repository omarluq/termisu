# High-level terminal interface combining I/O backend, Terminfo, and cell buffer.
#
# Provides a complete terminal UI API including:
# - Cell-based rendering with double buffering
# - Cursor movement and visibility
# - Colors and text attributes
# - Alternate screen mode
#
# Example:
# ```
# terminal = Termisu::Terminal.new
# terminal.enable_raw_mode
# terminal.enter_alternate_screen
#
# terminal.set_cell(10, 5, 'H', fg: Color.red)
# terminal.set_cell(11, 5, 'i', fg: Color.green)
# terminal.set_cursor(12, 5)
# terminal.render
#
# terminal.exit_alternate_screen
# terminal.close
# ```
class Termisu::Terminal < Termisu::Renderer
  @backend : Terminal::Backend
  @terminfo : Terminfo
  @buffer : Buffer
  @alternate_screen : Bool = false

  # Cached render state for direct API optimization.
  # Prevents redundant escape sequences when the same style is set repeatedly.
  @cached_fg : Color?
  @cached_bg : Color?
  @cached_attr : Attribute = Attribute::None
  @cached_cursor_visible : Bool?

  # Creates a new terminal.
  #
  # Parameters:
  # - `backend` - Terminal::Backend instance for I/O operations (default: Terminal::Backend.new)
  # - `terminfo` - Terminfo instance for capability strings (default: Terminfo.new)
  def initialize(
    @backend : Terminal::Backend = Terminal::Backend.new,
    @terminfo : Terminfo = Terminfo.new,
  )
    width, height = size
    @buffer = Buffer.new(width, height)
  end

  # Enters alternate screen mode.
  #
  # Switches to alternate screen buffer, clears the screen,
  # enters keypad mode, and hides cursor. Also resets cached
  # render state since we're entering a fresh screen.
  def enter_alternate_screen
    return if @alternate_screen
    write(@terminfo.enter_ca_seq)
    write(@terminfo.clear_screen_seq)
    write(@terminfo.enter_keypad_seq)
    reset_render_state
    @cached_cursor_visible = false # We're about to hide it
    write(@terminfo.hide_cursor_seq)
    flush
    @alternate_screen = true
  end

  # Exits alternate screen mode.
  #
  # Shows cursor, exits keypad mode, and returns to main screen buffer.
  # Also resets cached render state since we're returning to the
  # main screen which may have different state.
  def exit_alternate_screen
    return unless @alternate_screen
    @cached_cursor_visible = true # We're about to show it
    write(@terminfo.show_cursor_seq)
    write(@terminfo.exit_keypad_seq)
    write(@terminfo.exit_ca_seq)
    reset_render_state
    flush
    @alternate_screen = false
  end

  # Returns whether alternate screen mode is active.
  def alternate_screen? : Bool
    @alternate_screen
  end

  # Clears the screen.
  #
  # Writes the clear screen escape sequence immediately and flushes.
  # Also resets cached render state since screen content is cleared.
  def clear_screen
    write(@terminfo.clear_screen_seq)
    reset_render_state
    flush
  end

  # Resets the cached render state.
  #
  # Call this when the terminal state becomes unknown (e.g., after external
  # programs have modified the terminal, or after errors). This forces
  # the next color/attribute calls to emit escape sequences even if
  # the cached values match.
  #
  # The following operations automatically reset render state:
  # - enter_alternate_screen
  # - exit_alternate_screen
  # - clear_screen
  # - reset_attributes
  def reset_render_state
    @cached_fg = nil
    @cached_bg = nil
    @cached_attr = Attribute::None
    @cached_cursor_visible = nil
  end

  # Moves cursor to the specified position.
  #
  # Uses the terminfo `cup` capability with tparm processing for proper
  # terminal-specific cursor addressing. The cup capability handles the
  # 0-to-1 based coordinate conversion via the %i operation.
  #
  # Parameters:
  # - x: Column position (0-based)
  # - y: Row position (0-based)
  def move_cursor(x : Int32, y : Int32)
    # Note: cup uses (row, col) order, so y comes first
    seq = @terminfo.cursor_position_seq(y, x)
    if seq.empty?
      # Fallback to hardcoded ANSI if cup unavailable
      write("\e[#{y + 1};#{x + 1}H")
    else
      write(seq)
    end
  end

  # Sets the foreground color with full ANSI-8, ANSI-256, and RGB support.
  #
  # Caches the color to avoid redundant escape sequences when called
  # repeatedly with the same color.
  def foreground=(color : Color)
    return if @cached_fg == color
    @cached_fg = color

    if color.default?
      write("\e[39m") # Default foreground
    else
      case color.mode
      when .ansi8?
        write("\e[3#{color.index}m")
      when .ansi256?
        write("\e[38;5;#{color.index}m")
      when .rgb?
        write("\e[38;2;#{color.r};#{color.g};#{color.b}m")
      end
    end
  end

  # Sets the background color with full ANSI-8, ANSI-256, and RGB support.
  #
  # Caches the color to avoid redundant escape sequences when called
  # repeatedly with the same color.
  def background=(color : Color)
    return if @cached_bg == color
    @cached_bg = color

    if color.default?
      write("\e[49m") # Default background
    else
      case color.mode
      when .ansi8?
        write("\e[4#{color.index}m")
      when .ansi256?
        write("\e[48;5;#{color.index}m")
      when .rgb?
        write("\e[48;2;#{color.r};#{color.g};#{color.b}m")
      end
    end
  end

  # Writes show cursor escape sequence immediately.
  #
  # Caches visibility state to avoid redundant escape sequences.
  # Note: This is part of the Renderer interface, called by Buffer.
  # For buffer-based cursor control, use show_cursor instead.
  def write_show_cursor
    return if @cached_cursor_visible
    @cached_cursor_visible = true
    write(@terminfo.show_cursor_seq)
  end

  # Writes hide cursor escape sequence immediately.
  #
  # Caches visibility state to avoid redundant escape sequences.
  # Note: This is part of the Renderer interface, called by Buffer.
  # For buffer-based cursor control, use hide_cursor instead.
  def write_hide_cursor
    # Skip if cursor is already hidden (false). Don't skip if nil (unknown).
    cached = @cached_cursor_visible
    return if cached.is_a?(Bool) && !cached
    @cached_cursor_visible = false
    write(@terminfo.hide_cursor_seq)
  end

  # Resets all attributes to default.
  #
  # Also clears cached color/attribute state since reset affects all styling.
  def reset_attributes
    write(@terminfo.reset_attrs_seq)
    @cached_fg = nil
    @cached_bg = nil
    @cached_attr = Attribute::None
  end

  # Enables bold text.
  #
  # Caches attribute state to avoid redundant escape sequences.
  def enable_bold
    return if @cached_attr.bold?
    @cached_attr |= Attribute::Bold
    write(@terminfo.bold_seq)
  end

  # Enables underline.
  #
  # Caches attribute state to avoid redundant escape sequences.
  def enable_underline
    return if @cached_attr.underline?
    @cached_attr |= Attribute::Underline
    write(@terminfo.underline_seq)
  end

  # Enables blink.
  #
  # Caches attribute state to avoid redundant escape sequences.
  def enable_blink
    return if @cached_attr.blink?
    @cached_attr |= Attribute::Blink
    write(@terminfo.blink_seq)
  end

  # Enables reverse video.
  #
  # Caches attribute state to avoid redundant escape sequences.
  def enable_reverse
    return if @cached_attr.reverse?
    @cached_attr |= Attribute::Reverse
    write(@terminfo.reverse_seq)
  end

  # Enables dim/faint text.
  #
  # Caches attribute state to avoid redundant escape sequences.
  def enable_dim
    return if @cached_attr.dim?
    @cached_attr |= Attribute::Dim
    write(@terminfo.dim_seq)
  end

  # Enables italic/cursive text.
  #
  # Caches attribute state to avoid redundant escape sequences.
  def enable_cursive
    return if @cached_attr.cursive?
    @cached_attr |= Attribute::Cursive
    write(@terminfo.italic_seq)
  end

  # Enables hidden/invisible text.
  #
  # Caches attribute state to avoid redundant escape sequences.
  def enable_hidden
    return if @cached_attr.hidden?
    @cached_attr |= Attribute::Hidden
    write(@terminfo.hidden_seq)
  end

  # Delegates write to backend.
  def write(data : String)
    @backend.write(data)
  end

  # Delegates flush to backend.
  def flush
    @backend.flush
  end

  # Delegates size to backend.
  def size : {Int32, Int32}
    @backend.size
  end

  # Returns the input file descriptor for Reader.
  def infd : Int32
    @backend.infd
  end

  # Returns the output file descriptor.
  def outfd : Int32
    @backend.outfd
  end

  # Enables raw mode on the terminal.
  def enable_raw_mode
    @backend.enable_raw_mode
  end

  # Disables raw mode on the terminal.
  def disable_raw_mode
    @backend.disable_raw_mode
  end

  # Returns whether raw mode is currently enabled.
  def raw_mode? : Bool
    @backend.raw_mode?
  end

  # Executes a block with raw mode enabled, ensuring cleanup.
  def with_raw_mode(&)
    @backend.with_raw_mode { yield }
  end

  # Closes the terminal and underlying backend.
  def close
    @backend.close
  end

  # --- Cell Buffer Operations ---

  # Sets a cell at the specified position in the buffer.
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
  # Call render() to display changes on screen.
  def set_cell(
    x : Int32,
    y : Int32,
    ch : Char,
    fg : Color = Color.white,
    bg : Color = Color.default,
    attr : Attribute = Attribute::None,
  ) : Bool
    @buffer.set_cell(x, y, ch, fg, bg, attr)
  end

  # Gets a cell at the specified position from the buffer.
  #
  # Returns nil if coordinates are out of bounds.
  def get_cell(x : Int32, y : Int32) : Cell?
    @buffer.get_cell(x, y)
  end

  # Clears the cell buffer (fills with default cells).
  #
  # Call render() to display changes on screen.
  def clear_cells
    @buffer.clear
  end

  # Renders cell buffer changes to the screen.
  #
  # Only cells that have changed since the last render are redrawn (diff-based).
  # This is more efficient than full redraws for partial updates.
  def render
    @buffer.render_to(self)
  end

  # Forces a full redraw of all cells.
  #
  # Useful after terminal resize or screen corruption.
  def sync
    @buffer.sync_to(self)
  end

  # Sets cursor position in the buffer and makes it visible.
  #
  # Coordinates are clamped to buffer bounds.
  # Call render() to display the cursor on screen.
  def set_cursor(x : Int32, y : Int32)
    @buffer.set_cursor(x, y)
  end

  # Hides the cursor (rendered on next render()).
  def hide_cursor
    @buffer.hide_cursor
  end

  # Shows the cursor at current position (rendered on next render()).
  def show_cursor
    @buffer.show_cursor
  end

  # Resizes the buffer to new dimensions.
  #
  # Preserves existing content where possible.
  def resize_buffer(width : Int32, height : Int32)
    @buffer.resize(width, height)
  end
end

require "./terminal/*"
