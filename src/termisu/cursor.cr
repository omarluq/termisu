# Cursor manages cursor position and visibility.
#
# The cursor can be positioned at any cell or hidden.
# Following termbox-go's model, hidden cursor is represented by (-1, -1).
#
# Example:
# ```
# cursor = Termisu::Cursor.new
# cursor.move(10, 5)
# cursor.show
# cursor.hidden? # => false
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

  # Moves cursor to specified position and shows it.
  def move(x : Int32, y : Int32)
    @x = x
    @y = y
    @last_x = x
    @last_y = y
  end

  # Hides the cursor.
  def hide
    @x = HIDDEN
    @y = HIDDEN
  end

  # Shows the cursor at last position (or 0,0 if never positioned).
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
end
