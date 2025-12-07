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
  # enters keypad mode, and hides cursor.
  def enter_alternate_screen
    return if @alternate_screen
    write(@terminfo.enter_ca_seq)
    write(@terminfo.clear_screen_seq)
    write(@terminfo.enter_keypad_seq)
    write_hide_cursor
    flush
    @alternate_screen = true
  end

  # Exits alternate screen mode.
  #
  # Shows cursor, exits keypad mode, and returns to main screen buffer.
  def exit_alternate_screen
    return unless @alternate_screen
    write_show_cursor
    write(@terminfo.exit_keypad_seq)
    write(@terminfo.exit_ca_seq)
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
  def clear_screen
    write(@terminfo.clear_screen_seq)
    flush
  end

  # Moves cursor to the specified position.
  #
  # Note: This uses a simplified cursor addressing approach.
  # For full parametrized capability support, implement tparm.
  def move_cursor(x : Int32, y : Int32)
    # Using ANSI escape sequence as fallback
    # Full terminfo support would require tparm implementation
    write("\e[#{y + 1};#{x + 1}H")
  end

  # Sets the foreground color with full ANSI-8, ANSI-256, and RGB support.
  def foreground=(color : Color)
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
  def background=(color : Color)
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
  # Note: This is part of the Renderer interface, called by Buffer.
  # For buffer-based cursor control, use show_cursor instead.
  def write_show_cursor
    write(@terminfo.show_cursor_seq)
  end

  # Writes hide cursor escape sequence immediately.
  #
  # Note: This is part of the Renderer interface, called by Buffer.
  # For buffer-based cursor control, use hide_cursor instead.
  def write_hide_cursor
    write(@terminfo.hide_cursor_seq)
  end

  # Resets all attributes to default.
  def reset_attributes
    write(@terminfo.reset_attrs_seq)
  end

  # Enables bold text.
  def enable_bold
    write(@terminfo.bold_seq)
  end

  # Enables underline.
  def enable_underline
    write(@terminfo.underline_seq)
  end

  # Enables blink.
  def enable_blink
    write(@terminfo.blink_seq)
  end

  # Enables reverse video.
  def enable_reverse
    write(@terminfo.reverse_seq)
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
