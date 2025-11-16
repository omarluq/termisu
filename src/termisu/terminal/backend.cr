# Terminal-based backend implementation.
#
# Combines Terminal I/O with Terminfo capabilities to provide
# high-level rendering operations like cursor movement and colors.
#
# Example:
# ```
# terminal = Termisu::Terminal.new
# terminfo = Termisu::Terminfo.new
# backend = Termisu::Terminal::Backend.new(terminal, terminfo)
#
# backend.clear_screen
# backend.move_cursor(10, 5)
# backend.write("Hello!")
# backend.flush
# backend.close
# ```
class Termisu::Terminal::Backend < Termisu::Backend
  @terminal : Terminal
  @terminfo : Terminfo
  @alternate_screen : Bool = false

  # Creates a new terminal backend.
  #
  # - `terminal` - Terminal instance for I/O operations
  # - `terminfo` - Terminfo instance for capability strings
  def initialize(@terminal : Terminal, @terminfo : Terminfo)
  end

  # Enters alternate screen mode.
  #
  # Switches to alternate screen buffer, enters keypad mode,
  # hides cursor, and clears the screen.
  def enter_alternate_screen
    return if @alternate_screen
    write(@terminfo.enter_ca)
    write(@terminfo.enter_keypad)
    hide_cursor
    clear_screen
    flush
    @alternate_screen = true
  end

  # Exits alternate screen mode.
  #
  # Shows cursor, exits keypad mode, and returns to main screen buffer.
  def exit_alternate_screen
    return unless @alternate_screen
    show_cursor
    write(@terminfo.exit_keypad)
    write(@terminfo.exit_ca)
    flush
    @alternate_screen = false
  end

  # Returns whether alternate screen mode is active.
  def alternate_screen? : Bool
    @alternate_screen
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

  # Sets the foreground color (simplified ANSI color support).
  def foreground=(color : Int32)
    write("\e[3#{color}m")
  end

  # Sets the background color (simplified ANSI color support).
  def background=(color : Int32)
    write("\e[4#{color}m")
  end

  # Clears the screen using terminfo capability.
  def clear_screen
    write(@terminfo.clear_screen)
  end

  # Shows the cursor using terminfo capability.
  def show_cursor
    write(@terminfo.show_cursor)
  end

  # Hides the cursor using terminfo capability.
  def hide_cursor
    write(@terminfo.hide_cursor)
  end

  # Resets all attributes to default.
  def reset_attributes
    write(@terminfo.sgr0)
  end

  # Enables bold text.
  def enable_bold
    write(@terminfo.bold)
  end

  # Enables underline.
  def enable_underline
    write(@terminfo.underline)
  end

  # Enables blink.
  def enable_blink
    write(@terminfo.blink)
  end

  # Enables reverse video.
  def enable_reverse
    write(@terminfo.reverse)
  end

  # Delegates write to terminal.
  def write(data : String)
    @terminal.write(data)
  end

  # Delegates flush to terminal.
  def flush
    @terminal.flush
  end

  # Delegates size to terminal.
  def size : {Int32, Int32}
    @terminal.size
  end

  # Closes the backend and underlying terminal.
  def close
    @terminal.close
  end
end
