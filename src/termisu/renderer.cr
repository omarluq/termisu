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
  abstract def write(data : String, columns_advanced = 0)

  # Writes raw bytes to the renderer.
  #
  # Default implementation delegates to the String overload so existing
  # renderer implementations work unchanged. Terminal overrides this to
  # stream the bytes to the backend without materializing a String.
  def write(data : Bytes, columns_advanced = 0)
    write(String.new(data), columns_advanced)
  end

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
  abstract def show_cursor

  # Writes hide cursor escape sequence.
  abstract def hide_cursor

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

  # --- Combined Style Application ---

  # Applies a complete style transition (attributes + colors) in one call.
  #
  # *fg*, *bg*, and *attr* are the target style. The *old_* parameters carry
  # the caller's view of the current terminal style (`nil` = unknown, which
  # forces emission).
  #
  # This default implementation decomposes the transition into the granular
  # color/attribute methods above with the legacy emission semantics
  # (reset-then-reapply when any attribute is removed), so existing renderer
  # implementations need no changes. Terminal overrides this to emit a single
  # combined SGR sequence per transition instead.
  #
  # The branch count is a flat per-attribute dispatch table, not nested logic.
  # ameba:disable Metrics/CyclomaticComplexity
  def apply_sgr(
    fg : Color,
    bg : Color,
    attr : Attribute,
    old_fg : Color?,
    old_bg : Color?,
    old_attr : Attribute,
  ) : Nil
    if attr != old_attr
      if (old_attr & ~attr) != Attribute::None
        # Removing attributes requires a full reset, which also clears
        # colors, so they must be re-emitted below.
        reset_attributes
        old_attr = Attribute::None
        old_fg = nil
        old_bg = nil
      end
      enable_bold if attr.bold? && !old_attr.bold?
      enable_underline if attr.underline? && !old_attr.underline?
      enable_reverse if attr.reverse? && !old_attr.reverse?
      enable_blink if attr.blink? && !old_attr.blink?
      enable_dim if attr.dim? && !old_attr.dim?
      enable_cursive if attr.cursive? && !old_attr.cursive?
      enable_hidden if attr.hidden? && !old_attr.hidden?
      enable_strikethrough if attr.strikethrough? && !old_attr.strikethrough?
    end
    self.foreground = fg unless fg == old_fg
    self.background = bg unless bg == old_bg
  end
end
