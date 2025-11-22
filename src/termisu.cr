# Main Termisu class - Terminal User Interface library.
#
# Provides a clean, minimal API for terminal manipulation by delegating
# all logic to specialized components: Terminal, Backend, Reader, and Cell::Buffer.
#
# Example:
# ```
# termisu = Termisu.new
#
# # Set cells with colors and attributes
# termisu.set_cell(10, 5, 'H', fg: Color.red, bg: Color.black, attr: Attribute::Bold)
# termisu.set_cell(11, 5, 'i', fg: Color.green)
# termisu.set_cell(12, 5, '!', fg: Color.blue)
#
# # Flush applies changes (diff-based rendering)
# termisu.flush
#
# termisu.close
# ```
class Termisu
  VERSION = "0.0.1.alpha"

  # Initializes Termisu with all required components.
  #
  # Sets up terminal I/O, rendering backend, input reader, and cell buffer.
  # Automatically enables raw mode and enters alternate screen.
  def initialize
    @terminal = Terminal.new
    @terminfo = Terminfo.new
    @backend = Terminal::Backend.new(@terminal, @terminfo)
    @reader = Reader.new(@terminal.infd)

    # Initialize cell buffer with current terminal size
    width, height = size
    @buffer = Buffer.new(width, height)

    @terminal.enable_raw_mode
    @backend.enter_alternate_screen
  end

  # Closes Termisu and cleans up all resources.
  #
  # Exits alternate screen, disables raw mode, and closes all components.
  def close
    @backend.exit_alternate_screen
    @terminal.disable_raw_mode
    @reader.close
    @backend.close
  end

  # --- Terminal Operations ---

  delegate size, # Returns terminal size as {width, height}
    to: @terminal

  # --- Cursor Control ---

  delegate set_cursor, # Sets cursor position (x, y) and shows it
    hide_cursor,       # Hides the cursor
    show_cursor,       # Shows the cursor
    to: @buffer

  # --- Cell Buffer Operations ---

  # Sets a cell at the specified position.
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
  #
  # Example:
  # ```
  # termisu.set_cell(10, 5, 'A', fg: Color.red, attr: Attribute::Bold)
  # termisu.flush # Apply changes
  # ```
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

  # Clears the cell buffer (fills with spaces).
  #
  # Note: This clears the buffer, not the screen. Call flush() to apply.
  def clear
    @buffer.clear
  end

  # Flushes cell buffer changes to the screen.
  #
  # Only cells that have changed since the last flush are redrawn (diff-based rendering).
  # This is more efficient than clear_screen + write for partial updates.
  def flush
    @buffer.flush(@backend)
  end

  # Forces a full redraw of all cells.
  #
  # Useful after terminal resize or screen corruption.
  def sync
    @buffer.sync(@backend)
  end

  # --- Input Operations ---

  delegate read_byte, # Reads single byte, returns UInt8?
    read_bytes,       # Reads count bytes, returns Bytes?
    peek_byte,        # Peeks next byte without consuming, returns UInt8?
    to: @reader

  # Checks if input data is available.
  def input_available? : Bool
    @reader.available?
  end

  # Waits for input data with a timeout in milliseconds.
  def wait_for_input(timeout_ms : Int32) : Bool
    @reader.wait_for_data(timeout_ms)
  end
end

require "./termisu/*"
