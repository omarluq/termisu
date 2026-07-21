# Tracks the current terminal rendering state for optimization.
#
# Used to avoid emitting redundant escape sequences by tracking
# what colors and attributes are currently set.
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

  def initialize
    @fg, @bg, @attr = default_state
  end

  # Resets state to unknown (forces next render to emit all sequences).
  def reset
    @fg, @bg, @attr = default_state
  end

  # Applies style to renderer, only emitting changes.
  #
  # The full transition is delegated to `Renderer#apply_sgr` in one call so
  # renderers can coalesce it into a single escape sequence; the default
  # `apply_sgr` decomposes into the granular color/attribute methods with the
  # same emission semantics as before.
  #
  # Returns true if the style changed (i.e. the renderer was invoked).
  def apply_style(
    renderer : Renderer,
    fg : Color,
    bg : Color,
    attr : Attribute,
  ) : Bool
    return false if attr == @attr && fg == @fg && bg == @bg

    renderer.apply_sgr(fg, bg, attr, @fg, @bg, @attr)
    @fg = fg
    @bg = bg
    @attr = attr
    true
  end

  private def default_state : Tuple(Color?, Color?, Attribute)
    {nil, nil, Attribute::None}
  end
end
