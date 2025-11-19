# Cell represents a single character cell in the terminal buffer.
#
# Cell contains:
# - ch: The unicode character (rune)
# - fg: Foreground color (0-7 for basic ANSI, higher for extended)
# - bg: Background color (0-7 for basic ANSI, higher for extended)
# - attr: Text attributes (bold, underline, etc.)
#
# Example:
# ```
# cell = Termisu::Cell.new('A', fg: 2, bg: 0, attr: Termisu::Attribute::Bold)
# ```
struct Termisu::Cell
  property ch : Char
  property fg : Int32
  property bg : Int32
  property attr : Attribute

  # Creates a new Cell with the specified character and colors.
  #
  # Parameters:
  # - ch: Unicode character to display
  # - fg: Foreground color (Color enum or Int32, default: White)
  # - bg: Background color (Color enum or Int32, default: Default)
  # - attr: Text attributes (default: None)
  def initialize(
    @ch : Char = ' ',
    fg : Color | Int32 = Color::White,
    bg : Color | Int32 = Color::Default,
    @attr : Attribute = Attribute::None,
  )
    @fg = fg.is_a?(Color) ? fg.value : fg
    @bg = bg.is_a?(Color) ? bg.value : bg
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
    @fg = Color::White.value
    @bg = Color::Default.value
    @attr = Attribute::None
  end
end

require "./cell/*"
