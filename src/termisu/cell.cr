# Cell represents a single character cell in the terminal buffer.
#
# Cell contains:
# - ch: The unicode character (rune)
# - fg: Foreground color (supports ANSI-8, ANSI-256, and RGB)
# - bg: Background color (supports ANSI-8, ANSI-256, and RGB)
# - attr: Text attributes (bold, underline, etc.)
#
# Example:
# ```
# # Using named colors
# cell = Termisu::Cell.new('A', fg: Color.green, bg: Color.black, attr: Attribute::Bold)
#
# # Using 256-color palette
# cell = Termisu::Cell.new('B', fg: Color.ansi256(208), bg: Color.ansi256(235))
#
# # Using RGB/TrueColor
# cell = Termisu::Cell.new('C', fg: Color.rgb(255, 128, 64), bg: Color.rgb(30, 30, 30))
# ```
struct Termisu::Cell
  property ch : Char
  property fg : Color
  property bg : Color
  property attr : Attribute

  # Creates a new Cell with the specified character and colors.
  #
  # Parameters:
  # - ch: Unicode character to display
  # - fg: Foreground color (default: white)
  # - bg: Background color (default: default terminal color)
  # - attr: Text attributes (default: None)
  def initialize(
    @ch : Char = ' ',
    @fg : Color = Color.white,
    @bg : Color = Color.default,
    @attr : Attribute = Attribute::None,
  )
  end

  # Creates a default empty cell (space with default colors).
  def self.default : Cell
    new
  end

  # Checks if this cell equals another cell.
  def ==(other : Cell) : Bool
    @ch == other.ch && @fg == other.fg && @bg == other.bg && @attr == other.attr
  end

  # Resets the cell to default state (space, white on default background, no attributes).
  def reset
    @ch = ' '
    @fg = Color.white
    @bg = Color.default
    @attr = Attribute::None
  end
end
