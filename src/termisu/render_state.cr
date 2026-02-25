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
# state.apply_style(renderer, fg: Color.green, bg: Color.black, attr: Attribute::Bold)
#
# # Second cell with same style - no sequences emitted
# state.apply_style(renderer, fg: Color.green, bg: Color.black, attr: Attribute::Bold)
#
# # Third cell with different color - only color change emitted
# state.apply_style(renderer, fg: Color.red, bg: Color.black, attr: Attribute::Bold)
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

  # Applies style to renderer, only emitting changes.
  #
  # Returns true if any escape sequences were emitted.
  def apply_style(
    renderer : Renderer,
    fg : Color,
    bg : Color,
    attr : Attribute,
  ) : Bool
    changed = false

    # Handle attribute changes
    if attr != @attr
      apply_attribute_change(renderer, attr)
      changed = true
    end

    # Handle foreground color change
    if fg != @fg
      renderer.foreground = fg
      @fg = fg
      changed = true
    end

    # Handle background color change
    if bg != @bg
      renderer.background = bg
      @bg = bg
      changed = true
    end

    changed
  end

  # Moves cursor only if position changed.
  #
  # Returns true if cursor was moved.
  def move_cursor(renderer : Renderer, x : Int32, y : Int32) : Bool
    if x != @cursor_x || y != @cursor_y
      renderer.move_cursor(x, y)
      @cursor_x = x
      @cursor_y = y
      true
    else
      false
    end
  end

  # Advances cursor X position without emitting escape sequence.
  # Used when writing characters (cursor moves automatically).
  # For wide characters, pass columns = 2.
  def advance_cursor(columns : Int32 = 1)
    if current_x = @cursor_x
      @cursor_x = current_x + columns
    end
  end

  # Checks if cursor is at the expected position for a horizontal write.
  def cursor_at?(x : Int32, y : Int32) : Bool
    @cursor_x == x && @cursor_y == y
  end

  private def apply_attribute_change(renderer : Renderer, new_attr : Attribute)
    reset_if_removing_attrs(renderer, new_attr)
    apply_new_attributes(renderer, new_attr)
    @attr = new_attr
  end

  # Resets all attributes if any are being removed.
  private def reset_if_removing_attrs(renderer : Renderer, new_attr : Attribute)
    if (@attr & ~new_attr) != Attribute::None
      renderer.reset_attributes
      @fg = nil # Reset clears colors too
      @bg = nil
    end
  end

  # Applies individual attributes that are newly enabled.
  private def apply_new_attributes(renderer : Renderer, new_attr : Attribute)
    renderer.enable_bold if needs_attr?(new_attr, Attribute::Bold)
    renderer.enable_underline if needs_attr?(new_attr, Attribute::Underline)
    renderer.enable_reverse if needs_attr?(new_attr, Attribute::Reverse)
    renderer.enable_blink if needs_attr?(new_attr, Attribute::Blink)
    renderer.enable_dim if needs_attr?(new_attr, Attribute::Dim)
    renderer.enable_cursive if needs_attr?(new_attr, Attribute::Cursive)
    renderer.enable_hidden if needs_attr?(new_attr, Attribute::Hidden)
    renderer.enable_strikethrough if needs_attr?(new_attr, Attribute::Strikethrough)
  end

  # Checks if an attribute needs to be enabled (present in new but not current).
  private def needs_attr?(new_attr : Attribute, flag : Attribute) : Bool
    new_attr.includes?(flag) && !@attr.includes?(flag)
  end
end
