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
# The `grapheme` property provides backward-compatible access:
# ```
# cell = Termisu::Cell.new("ABC")
# cell.grapheme # => "A" (first grapheme of input-String is stored)
#
# continuation = Termisu::Cell.continuation
# continuation.grapheme # => "" (empty for continuation cells)
# ```
struct Termisu::Cell
  getter grapheme : String = ""
  getter width : UInt8 = 0
  getter? continuation : Bool
  property fg : Color
  property bg : Color
  property attr : Attribute

  # default empty cell (space with default colors, width 1, not continuation).
  class_getter default = Cell.new

  # Continuation cells represent the trailing column occupied by a wide character.
  # They have empty grapheme, width 0, and are never rendered directly.
  #
  # ```
  # trail = Termisu::Cell.continuation
  # trail.continuation? # => true
  # trail.width         # => 0
  # trail.grapheme      # => ""
  # ```
  class_getter continuation = Cell.new(continuation: true)

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
    @continuation : Bool = false,
    @fg : Color = Color.white,
    @bg : Color = Color.default,
    @attr : Attribute = Attribute::None,
  )
    self.grapheme = grapheme
  end

  def grapheme=(@grapheme)
    if @continuation
      @grapheme = ""
      @width = 0u8
    elsif grapheme.empty?
      @grapheme = " "
      @width = 1u8
    elsif grapheme.bytesize == 1 && grapheme.to_unsafe[0] < 0x80
      # ASCII fast path: a single byte < 0x80 is by definition exactly one
      # grapheme cluster, so grapheme extraction (GraphemeIterator + Char#to_s,
      # two heap allocations) and the truncation log are no-ops here.
      # Width mirrors UnicodeWidth.grapheme_width over the whole ASCII range:
      # C0 controls (< 0x20) and DEL (0x7F) are zero-width, everything else 1.
      # Single bytes >= 0x80 are invalid UTF-8 and MUST fall through to the
      # slow path so its existing behavior (raw byte stored, width 1) is
      # preserved bit-for-bit. Do not "fix" this comment to say U+FFFD — the
      # slow path does NOT substitute the replacement character.
      byte = grapheme.to_unsafe[0]
      @width = byte < 0x20 || byte == 0x7F ? 0u8 : 1u8
    else
      # Extract first grapheme cluster to ensure single-grapheme invariant
      first = grapheme.each_grapheme.first.to_s
      if first.bytesize < grapheme.bytesize
        Termisu::Logs::Buffer.debug { "Cell: multi-grapheme input truncated (#{grapheme.grapheme_size} graphemes, kept first)" }
      end
      @grapheme = first
      @width = UnicodeWidth.grapheme_width(@grapheme)
    end
  end

  # Returns true when this cell is the canonical default blank cell.
  #
  # Used by Buffer hot paths (clear/dirtiness accounting) to avoid
  # expensive full-buffer work when rows are already blank.
  def default_state? : Bool
    self == Cell.default
  end
end
