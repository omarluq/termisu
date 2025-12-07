# Tracks the current terminal rendering state for optimization.
#
# Used to avoid emitting redundant escape sequences by tracking
# what colors, attributes, and cursor position are currently set.
# Only emits escape sequences when the state actually changes.
#
# Example:
# ```
# state = Termisu::RenderState.new
#
# # First cell - emits all sequences
# state.apply_style(backend, fg: Color.green, bg: Color.black, attr: Attribute::Bold)
#
# # Second cell with same style - no sequences emitted
# state.apply_style(backend, fg: Color.green, bg: Color.black, attr: Attribute::Bold)
#
# # Third cell with different color - only color change emitted
# state.apply_style(backend, fg: Color.red, bg: Color.black, attr: Attribute::Bold)
# ```
struct Termisu::RenderState
  # Current foreground color (nil = unknown/reset)
  property fg : Color?

  # Current background color (nil = unknown/reset)
  property bg : Color?

  # Current text attributes
  property attr : Attribute

  # Current cursor X position (nil = unknown)
  property cursor_x : Int32?

  # Current cursor Y position (nil = unknown)
  property cursor_y : Int32?

  def initialize
    @fg = nil
    @bg = nil
    @attr = Attribute::None
    @cursor_x = nil
    @cursor_y = nil
  end

  # Resets state to unknown (forces next render to emit all sequences).
  def reset
    @fg = nil
    @bg = nil
    @attr = Attribute::None
    @cursor_x = nil
    @cursor_y = nil
  end

  # Applies style to backend, only emitting changes.
  #
  # Returns true if any escape sequences were emitted.
  def apply_style(
    backend : Backend,
    fg : Color,
    bg : Color,
    attr : Attribute,
  ) : Bool
    changed = false

    # Handle attribute changes
    if attr != @attr
      apply_attribute_change(backend, attr)
      changed = true
    end

    # Handle foreground color change
    if fg != @fg
      backend.foreground = fg
      @fg = fg
      changed = true
    end

    # Handle background color change
    if bg != @bg
      backend.background = bg
      @bg = bg
      changed = true
    end

    changed
  end

  # Moves cursor only if position changed.
  #
  # Returns true if cursor was moved.
  def move_cursor(backend : Backend, x : Int32, y : Int32) : Bool
    if x != @cursor_x || y != @cursor_y
      backend.move_cursor(x, y)
      @cursor_x = x
      @cursor_y = y
      true
    else
      false
    end
  end

  # Advances cursor X position without emitting escape sequence.
  # Used when writing characters (cursor moves automatically).
  def advance_cursor
    if current_x = @cursor_x
      @cursor_x = current_x + 1
    end
  end

  # Checks if cursor is at the expected position for a horizontal write.
  def cursor_at?(x : Int32, y : Int32) : Bool
    @cursor_x == x && @cursor_y == y
  end

  private def apply_attribute_change(backend : Backend, new_attr : Attribute)
    # If any attributes are being removed, we need to reset first
    if (@attr & ~new_attr) != Attribute::None
      backend.reset_attributes
      @fg = nil # Reset clears colors too
      @bg = nil
    end

    # Apply new attributes
    backend.enable_bold if new_attr.bold? && !@attr.bold?
    backend.enable_underline if new_attr.underline? && !@attr.underline?
    backend.enable_reverse if new_attr.reverse? && !@attr.reverse?
    backend.enable_blink if new_attr.blink? && !@attr.blink?

    @attr = new_attr
  end
end
