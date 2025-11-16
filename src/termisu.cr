# Main Termisu class - Terminal User Interface library.
#
# Provides a clean, minimal API for terminal manipulation by delegating
# all logic to specialized components: Terminal, Backend, and Reader.
#
# Example:
# ```
# termisu = Termisu.new
# termisu.clear_screen
# termisu.move_cursor(10, 5)
# termisu.write("Hello, Termisu!")
# termisu.flush
# termisu.close
# ```
class Termisu
  VERSION = "0.0.1.alpha"

  # Initializes Termisu with all required components.
  #
  # Sets up terminal I/O, rendering backend, and input reader.
  # Automatically enables raw mode and enters alternate screen.
  def initialize
    @terminal = Terminal.new
    @terminfo = Terminfo.new
    @backend = Terminal::Backend.new(@terminal, @terminfo)
    @reader = Reader.new(@terminal.infd)

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

  # --- Rendering Operations ---

  delegate clear_screen, # Clears the entire screen
    move_cursor,         # Moves cursor to x, y coordinates (0-based)
    show_cursor,         # Shows the cursor
    hide_cursor,         # Hides the cursor
    reset_attributes,    # Resets all text attributes to default
    enable_bold,         # Enables bold text
    enable_underline,    # Enables underlined text
    enable_blink,        # Enables blinking text
    enable_reverse,      # Enables reverse video (swap fg/bg)
    write,               # Writes string to terminal (buffered)
    flush,               # Flushes buffered output
    to: @backend

  # Sets foreground text color (0-7)
  def foreground=(color : Int32)
    @backend.foreground = color
  end

  # Sets background color (0-7)
  def background=(color : Int32)
    @backend.background = color
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
