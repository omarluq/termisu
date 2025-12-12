# Abstract renderer interface for terminal output.
#
# Separates rendering logic from I/O operations, enabling
# different renderer implementations (terminal, in-memory, etc.).
#
# This interface defines all methods that Buffer requires for rendering
# cells to the screen, including cursor control, colors, and attributes.
#
# Note: Methods with `_seq` suffix write escape sequences immediately.
# This distinguishes them from buffer state management methods.
abstract class Termisu::Renderer
  # --- Core I/O ---

  # Writes data to the renderer.
  abstract def write(data : String)

  # Flushes any buffered output.
  abstract def flush

  # Returns the renderer dimensions as {width, height}.
  abstract def size : {Int32, Int32}

  # Closes the renderer and releases resources.
  abstract def close

  # --- Cursor Control ---

  # Moves cursor to the specified position (writes escape sequence).
  abstract def move_cursor(x : Int32, y : Int32)

  # Writes show cursor escape sequence.
  abstract def write_show_cursor

  # Writes hide cursor escape sequence.
  abstract def write_hide_cursor

  # --- Color Control ---

  # Sets the foreground color (writes escape sequence).
  abstract def foreground=(color : Color)

  # Sets the background color (writes escape sequence).
  abstract def background=(color : Color)

  # --- Text Attributes ---

  # Resets all text attributes to default (writes escape sequence).
  abstract def reset_attributes

  # Enables bold text (writes escape sequence).
  abstract def enable_bold

  # Enables underline text (writes escape sequence).
  abstract def enable_underline

  # Enables reverse video (writes escape sequence).
  abstract def enable_reverse

  # Enables blink text (writes escape sequence).
  abstract def enable_blink

  # Enables dim/faint text (writes escape sequence).
  abstract def enable_dim

  # Enables italic/cursive text (writes escape sequence).
  abstract def enable_cursive

  # Enables hidden/invisible text (writes escape sequence).
  abstract def enable_hidden

  # Enables strikethrough text (writes escape sequence).
  abstract def enable_strikethrough
end
