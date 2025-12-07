# Cursor manages cursor position and visibility state.
#
# The cursor tracks both position (x, y) and visibility.
# Hidden cursor is represented by (-1, -1) coordinates.
#
# Example:
# ```
# cursor = Termisu::Cursor.new
# cursor.set_position(10, 5)
# cursor.visible? # => true (set_position shows cursor)
#
# cursor.hide
# cursor.hidden? # => true
#
# cursor.show # restores to last position
# ```
class Termisu::Cursor
  HIDDEN = -1

  property x : Int32
  property y : Int32

  @last_x : Int32?
  @last_y : Int32?

  # Creates a new cursor, hidden by default.
  def initialize
    @x = HIDDEN
    @y = HIDDEN
    @last_x = nil
    @last_y = nil
  end

  # Sets cursor position and makes it visible.
  #
  # Note: This method has a side effect of showing the cursor.
  # Use hide() after if you want to position without showing.
  def set_position(x : Int32, y : Int32)
    @x = x
    @y = y
    @last_x = x
    @last_y = y
  end

  # Hides the cursor (sets position to HIDDEN).
  def hide
    @x = HIDDEN
    @y = HIDDEN
  end

  # Shows the cursor at last known position (or 0,0 if never positioned).
  def show
    return unless hidden?

    if @last_x && @last_y
      @x = @last_x.as(Int32)
      @y = @last_y.as(Int32)
    else
      @x = 0
      @y = 0
      @last_x = 0
      @last_y = 0
    end
  end

  # Returns true if cursor is hidden.
  def hidden? : Bool
    @x == HIDDEN && @y == HIDDEN
  end

  # Returns true if cursor is visible.
  def visible? : Bool
    !hidden?
  end

  # Clamps cursor position to be within the given bounds.
  #
  # If cursor is hidden, it remains hidden but last_x/last_y are clamped.
  # If cursor is visible and outside bounds, it's clamped to max valid position.
  def clamp(max_x : Int32, max_y : Int32)
    return if max_x <= 0 || max_y <= 0

    # Clamp visible cursor position
    unless hidden?
      @x = @x.clamp(0, max_x - 1)
      @y = @y.clamp(0, max_y - 1)
    end

    # Clamp last known position (used when showing hidden cursor)
    if @last_x
      @last_x = @last_x.as(Int32).clamp(0, max_x - 1)
    end
    if @last_y
      @last_y = @last_y.as(Int32).clamp(0, max_y - 1)
    end
  end
end
