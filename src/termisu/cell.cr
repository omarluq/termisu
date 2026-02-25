# Cell represents a single character cell in the terminal buffer.
#
# Cell contains:
# - grapheme: The Unicode grapheme cluster (single grapheme for leading cells)
# - width: Display column width (0, 1, or 2)
# - continuation: True for trailing cell of a wide grapheme
# - fg: Foreground color (supports ANSI-8, ANSI-256, and RGB)
# - bg: Background color (supports ANSI-8, ANSI-256, and RGB)
# - attr: Text attributes (bold, underline, etc.)
#
# ## Grapheme and Continuation Cells
#
# Wide characters (CJK, emoji) occupy 2 columns. The Cell model represents this:
# - Leading cell: `continuation = false`, `width = 2`, `grapheme` contains the full grapheme
# - Trailing cell: `continuation = true`, `width = 0`, `grapheme` is empty
#
# Example:
# ```
# # Leading cell for "中" (width auto-calculated as 2)
# lead = Termisu::Cell.new("中")
# lead.grapheme      # => "中"
# lead.width         # => 2
# lead.continuation? # => false
#
# # Trailing continuation cell
# trail = Termisu::Cell.continuation
# trail.grapheme      # => ""
# trail.width         # => 0
# trail.continuation? # => true
# ```
#
# ## Compatibility (Public API)
#
# The `ch` property provides backward-compatible access:
# ```
# cell = Termisu::Cell.new('A')
# cell.ch # => 'A' (first codepoint of grapheme)
#
# continuation = Termisu::Cell.continuation
# continuation.ch # => ' ' (space for continuation cells)
# ```
struct Termisu::Cell
  getter grapheme : String
  getter width : UInt8
  getter? continuation : Bool
  property fg : Color
  property bg : Color
  property attr : Attribute

  # Creates a new Cell with the specified grapheme and colors.
  #
  # Parameters:
  # - grapheme: Unicode grapheme cluster to display (if multi-grapheme string is
  #   passed, only the first grapheme cluster is stored)
  # - continuation: True if this is a trailing cell of a wide grapheme
  # - fg: Foreground color (default: white)
  # - bg: Background color (default: default terminal color)
  # - attr: Text attributes (default: None)
  #
  # Note: Width is derived from grapheme content to ensure consistency.
  # Continuation cells always have empty grapheme and width 0.
  #
  # Occupancy invariants enforced:
  # - Continuation cells: always empty grapheme, width 0
  # - Empty non-continuation: normalized to default space cell (width 1)
  # - Leading cells: width derived via grapheme_width (handles VS16, ZWJ, flags)
  # - Multi-grapheme strings: only first grapheme is stored; debug log warns of truncation
  def initialize(
    grapheme : String = " ",
    continuation : Bool = false,
    @fg : Color = Color.white,
    @bg : Color = Color.default,
    @attr : Attribute = Attribute::None,
  )
    # Normalize state to enforce occupancy invariants
    if continuation
      @grapheme = ""
      @width = 0u8
      @continuation = true
    elsif grapheme.empty?
      @grapheme = " "
      @width = 1u8
      @continuation = false
    else
      # Extract first grapheme cluster to ensure single-grapheme invariant
      first = grapheme.each_grapheme.first.to_s
      if first.bytesize < grapheme.bytesize
        Termisu::Logs::Buffer.debug { "Cell: multi-grapheme input truncated (#{grapheme.size} graphemes, kept first)" }
      end
      @grapheme = first
      @width = UnicodeWidth.grapheme_width(@grapheme)
      @continuation = false
    end
  end

  # Creates a Cell from a single character (compatibility constructor).
  #
  # This constructor maintains backward compatibility with the Char-based API.
  # Width is auto-calculated from the character's codepoint.
  #
  # Note: Control characters (C0/C1) produce width 0 non-continuation cells.
  # This is permitted for internal sentinel usage (e.g., Buffer#invalidate uses
  # NUL cells as invalid markers). The public write path (Buffer#set_cell) guards
  # against control characters before reaching this constructor.
  def self.new(ch : Char, fg : Color = Color.white, bg : Color = Color.default, attr : Attribute = Attribute::None) : self
    new(ch.to_s, fg: fg, bg: bg, attr: attr)
  end

  # Creates a default empty cell (space with default colors, width 1, not continuation).
  def self.default : Cell
    new
  end

  # Creates a continuation cell for wide graphemes.
  #
  # Continuation cells represent the trailing column occupied by a wide character.
  # They have empty grapheme, width 0, and are never rendered directly.
  #
  # ```
  # trail = Termisu::Cell.continuation
  # trail.continuation? # => true
  # trail.width         # => 0
  # trail.grapheme      # => ""
  # ```
  def self.continuation : Cell
    new(continuation: true)
  end

  # Checks if this cell equals another cell.
  #
  # Two cells are equal if all fields match: grapheme, width, continuation, fg, bg, attr.
  def ==(other : Cell) : Bool
    @grapheme == other.grapheme &&
      @width == other.width &&
      @continuation == other.continuation? &&
      @fg == other.fg &&
      @bg == other.bg &&
      @attr == other.attr
  end

  # Resets the cell to default state (space, white on default background, no attributes, width 1, not continuation).
  def reset
    @grapheme = " "
    @width = 1u8
    @continuation = false
    @fg = Color.white
    @bg = Color.default
    @attr = Attribute::None
  end

  # Gets the first character of the grapheme (compatibility property).
  #
  # Returns:
  # - First codepoint of grapheme for leading cells
  # - Space (' ') for continuation cells or empty grapheme
  #
  # This provides backward compatibility with Char-based API.
  def ch : Char
    return ' ' if @continuation || @grapheme.empty?
    @grapheme.chars.first || ' '
  end

  # Sets the cell to a single character (compatibility setter).
  #
  # This rewrites the cell to narrow grapheme mode with width calculated
  # from the character's codepoint.
  #
  # Provides backward compatibility with Char-based API.
  def ch=(value : Char)
    @grapheme = value.to_s
    @width = UnicodeWidth.codepoint_width(value.ord)
    @continuation = false
  end
end
