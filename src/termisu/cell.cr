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
  getter fg : Color
  getter bg : Color
  getter attr : Attribute

  # Packed identity key: equal keys <=> equal cells (memberwise equality).
  # Buffer hot paths (write dedup, diff scan, default_state?) compare this
  # single UInt128 instead of walking the struct field-by-field.
  #
  # Bit layout (LSB first):
  # - 0..15    attr (UInt16 flags value)
  # - 16..49   fg color key (2-bit mode + 32-bit canonical payload)
  # - 50..83   bg color key (same encoding)
  # - 84..115  grapheme id (ASCII byte direct; non-ASCII interned)
  # - 116..117 width (0..2)
  # - 118      continuation flag
  #
  # Injectivity notes: color payload encodes exactly the fields Color#==
  # compares per mode (index for ANSI, r/g/b for RGB), and public Color
  # constructors zero the unused fields, so equal color keys imply Color#==.
  # Grapheme ids are content-interned, so equal ids imply equal strings.
  getter key : UInt128 = 0

  private CONTINUATION_BIT = 1_u128 << 118

  # Key of the canonical default cell, resolved lazily so default_state?
  # stays a single integer compare.
  DEFAULT_KEY = Cell.new.key

  # Key of the canonical continuation cell, so Buffer's key planes can write
  # continuation cells without materializing a Cell.
  CONTINUATION_KEY = Cell.new(continuation: true).key

  # Style portion of a key (attr + fg + bg, bits 0..83). Cells with equal
  # masked keys render with identical styling (see injectivity notes on #key).
  KEY_STYLE_MASK = (1_u128 << 84) - 1

  # Intern table assigning each distinct non-ASCII grapheme a stable 32-bit
  # id for key packing. No reverse lookup is ever needed (emission reads the
  # stored String), so the table only grows; the distinct grapheme count per
  # process is bounded in practice. Mutex-guarded because cells may be
  # constructed from any fiber or thread.
  @@grapheme_intern = {} of String => UInt32
  @@grapheme_intern_mutex = Mutex.new

  # Non-ASCII ids start above the directly-encoded ASCII byte range.
  private INTERN_BASE = 0x80_u32

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

  # Style setters splice only their own key field instead of re-running
  # compute_key, which would re-derive the grapheme id and take the
  # process-global intern mutex for non-ASCII cells.
  def fg=(@fg : Color)
    @key = (@key & ~FG_KEY_MASK) | (UInt128.new(Cell.color_key(@fg)) << 16)
  end

  def bg=(@bg : Color)
    @key = (@key & ~BG_KEY_MASK) | (UInt128.new(Cell.color_key(@bg)) << 50)
  end

  def attr=(@attr : Attribute)
    @key = (@key & ~ATTR_KEY_MASK) | UInt128.new(@attr.value)
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
      # cluster paths below so their existing behavior (raw byte stored,
      # width 1) is preserved bit-for-bit. Do not "fix" this comment to say
      # U+FFFD — neither path substitutes the replacement character.
      byte = grapheme.to_unsafe[0]
      @width = byte < 0x20 || byte == 0x7F ? 0u8 : 1u8
    elsif grapheme.grapheme_size == 1
      # Single-cluster input (every CJK/emoji cell) already satisfies the
      # single-grapheme invariant, so keep the auto-assigned input String:
      # Strings are immutable, and grapheme_size walks cluster boundaries
      # without materializing Grapheme values, making this path zero-alloc
      # (vs. 80-112 B/op for the extraction below).
      @width = UnicodeWidth.grapheme_width(grapheme)
    else
      # Extract first grapheme cluster to ensure single-grapheme invariant
      first = grapheme.each_grapheme.first.to_s
      if first.bytesize < grapheme.bytesize
        Termisu::Logs::Buffer.debug { "Cell: multi-grapheme input truncated (#{grapheme.grapheme_size} graphemes, kept first)" }
      end
      @grapheme = first
      @width = UnicodeWidth.grapheme_width(@grapheme)
    end
    @key = compute_key
  end

  # Returns true when this cell is the canonical default blank cell.
  #
  # Used by Buffer hot paths (clear/dirtiness accounting) to avoid
  # expensive full-buffer work when rows are already blank.
  def default_state? : Bool
    @key == DEFAULT_KEY
  end

  private def compute_key : UInt128
    key = UInt128.new(@attr.value)
    key |= UInt128.new(Cell.color_key(@fg)) << 16
    key |= UInt128.new(Cell.color_key(@bg)) << 50
    key |= UInt128.new(Cell.grapheme_id(@grapheme)) << 84
    key |= UInt128.new(@width) << 116
    key |= CONTINUATION_BIT if @continuation
    key
  end

  # 34-bit color key: bits 32..33 carry the mode so equal keys always imply
  # same-mode Color#== equality.
  protected def self.color_key(color : Color) : UInt64
    case color.mode
    in .ansi8?
      # index -1 (default) .. 7 shifted into 0..8
      (color.index + 1).to_u64
    in .ansi256?
      # index -1 (default) .. 255 shifted into 0..256
      (1_u64 << 32) | (color.index + 1).to_u64
    in .rgb?
      (2_u64 << 32) | (color.r.to_u64 << 16) | (color.g.to_u64 << 8) | color.b.to_u64
    end
  end

  # --- Key-plane decoding (Buffer SoA storage) ---
  # Buffer stores cells as bare keys plus a grapheme plane; these helpers
  # decode key fields without materializing a Cell. Bit positions must stay
  # in lockstep with compute_key.

  protected def self.key_width(key : UInt128) : Int32
    ((key >> 116).to_u8! & 0b11).to_i32
  end

  protected def self.key_continuation?(key : UInt128) : Bool
    (key & CONTINUATION_BIT) != 0
  end

  protected def self.key_grapheme_id(key : UInt128) : UInt32
    (key >> 84).to_u32!
  end

  # True when the key's grapheme is interned (non-ASCII), meaning the String
  # lives in Buffer's grapheme plane rather than being decodable from the key.
  protected def self.key_grapheme_interned?(key : UInt128) : Bool
    key_grapheme_id(key) >= INTERN_BASE
  end

  protected def self.key_attr(key : UInt128) : Attribute
    Attribute.new(key.to_u16!)
  end

  protected def self.key_fg(key : UInt128) : Color
    color_from_key((key >> 16).to_u64! & COLOR_KEY_MASK)
  end

  protected def self.key_bg(key : UInt128) : Color
    color_from_key((key >> 50).to_u64! & COLOR_KEY_MASK)
  end

  # Reconstructs a Cell value from its key and grapheme (cold path: get_cell).
  # Width and key are re-derived from the grapheme, which round-trips exactly
  # because the key was produced from the same grapheme content.
  protected def self.from_key(key : UInt128, grapheme : String) : Cell
    new(grapheme,
      continuation: key_continuation?(key),
      fg: key_fg(key),
      bg: key_bg(key),
      attr: key_attr(key))
  end

  private COLOR_KEY_MASK = (1_u64 << 34) - 1

  # Per-field key masks for the style setters (bit positions per #key layout).
  private ATTR_KEY_MASK = UInt128.new(UInt16::MAX)
  private FG_KEY_MASK   = UInt128.new(COLOR_KEY_MASK) << 16
  private BG_KEY_MASK   = UInt128.new(COLOR_KEY_MASK) << 50

  # Inverse of color_key: payload always came from a validated Color, so the
  # public constructors' validation cannot fail here.
  private def self.color_from_key(key : UInt64) : Color
    payload = (key & 0xFFFF_FFFF).to_i32
    case key >> 32
    when 0 then Color.ansi8(payload - 1)
    when 1 then Color.ansi256(payload - 1)
    else        Color.rgb((payload >> 16) & 0xFF, (payload >> 8) & 0xFF, payload & 0xFF)
    end
  end

  # ASCII graphemes (single byte < 0x80) encode their byte directly; the
  # empty grapheme (continuation cells) is id 0, disambiguated from NUL
  # sentinels by the width/continuation bits. Everything else is interned.
  protected def self.grapheme_id(grapheme : String) : UInt32
    return 0_u32 if grapheme.empty?

    byte = grapheme.to_unsafe[0]
    return byte.to_u32 if grapheme.bytesize == 1 && byte < 0x80

    @@grapheme_intern_mutex.synchronize do
      @@grapheme_intern.put_if_absent(grapheme) { INTERN_BASE + @@grapheme_intern.size.to_u32 }
    end
  end
end
