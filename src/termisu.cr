# Main Termisu class - Terminal User Interface library.
#
# Provides a clean, minimal API for terminal manipulation by delegating
# all logic to specialized components: Terminal and Reader.
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
# # Render applies changes (diff-based rendering)
# termisu.render
#
# termisu.close
# ```
class Termisu
  VERSION = "0.0.1.alpha"

  # Initializes Termisu with all required components.
  #
  # Sets up terminal I/O, rendering, and input reader.
  # Automatically enables raw mode and enters alternate screen.
  def initialize
    Logging.setup

    Log.info { "Initializing Termisu v#{VERSION}" }

    @terminal = Terminal.new
    @reader = Reader.new(@terminal.infd)

    Log.debug { "Terminal size: #{@terminal.size}" }

    @terminal.enable_raw_mode
    @terminal.enter_alternate_screen

    Log.debug { "Raw mode enabled, alternate screen entered" }
  end

  # Closes Termisu and cleans up all resources.
  #
  # Exits alternate screen, disables raw mode, and closes all components.
  def close
    Log.info { "Closing Termisu" }

    @terminal.exit_alternate_screen
    @terminal.disable_raw_mode
    @reader.close
    @terminal.close

    Logging.flush
    Logging.close
  end

  # --- Terminal Operations ---

  # Returns the underlying terminal for direct access.
  getter terminal : Terminal

  # Returns terminal size as {width, height}.
  delegate size, to: @terminal

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
  # termisu.render # Apply changes
  # ```
  delegate set_cell, to: @terminal

  # Clears the cell buffer (fills with spaces).
  #
  # Note: This clears the buffer, not the screen. Call render() to apply.
  def clear
    @terminal.clear_cells
  end

  # Renders cell buffer changes to the screen.
  #
  # Only cells that have changed since the last render are redrawn (diff-based).
  # This is more efficient than clear_screen + write for partial updates.
  delegate render, to: @terminal

  # Forces a full redraw of all cells.
  #
  # Useful after terminal resize or screen corruption.
  delegate sync, to: @terminal

  # --- Cursor Control ---

  # Sets cursor position and makes it visible.
  # Hides the cursor (rendered on next render()).
  # Shows the cursor (rendered on next render()).
  delegate set_cursor, hide_cursor, show_cursor, to: @terminal

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
