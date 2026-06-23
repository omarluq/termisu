module Termisu::Testing
  # A minimal terminal emulator: feed it the byte stream a Termisu program writes
  # and it maintains a 2D grid of `Termisu::Cell` plus a cursor, so tests can
  # assert on what's rendered (`get_by_text`, `cursor`, `to_s` snapshot).
  #
  # Scope: it decodes the subset Termisu emits (absolute cursor positioning,
  # erase, SGR colors/attrs, printable text with wide-char placement) and
  # recognizes-and-skips the rest (DEC private modes, mouse, kitty, OSC). It is
  # NOT a full VT525 — it does not implement scroll regions, tab stops, or insert
  # mode, which Termisu never emits. The grapheme/width logic reuses
  # `Termisu::UnicodeWidth` so columns match the program's own cursor tracking.
  #
  # `#feed` is incremental and keeps parser state across calls, so PTY reads that
  # split an escape sequence mid-stream are handled correctly.
  class Screen
    getter rows : Int32
    getter cols : Int32
    getter cursor_x : Int32 = 0
    getter cursor_y : Int32 = 0
    getter? cursor_visible : Bool = true

    # Parser state machine.
    private enum State
      Ground
      Escape
      Csi
      Osc
      OscEsc
      Charset
    end

    @grid : Array(Array(Cell))
    @state : State = State::Ground
    @params : Array(Int32) = [] of Int32
    @cur_param : Int32? = nil
    @csi_prefix : Char? = nil
    @csi_intermediate : Char? = nil
    # Pen (current graphic rendition applied to written glyphs).
    @pen_fg : Color = Color.default
    @pen_bg : Color = Color.default
    @pen_attr : Attribute = Attribute::None
    # In-progress UTF-8 codepoint accumulation.
    @utf8 : Array(UInt8) = [] of UInt8
    @utf8_need : Int32 = 0

    def initialize(@cols : Int32, @rows : Int32)
      @grid = Array.new(@rows) { Array.new(@cols) { Cell.default } }
    end

    # Feed a chunk of output bytes. Safe to call repeatedly with partial data.
    def feed(bytes : Bytes) : Nil
      bytes.each { |byte| consume(byte) }
    end

    def feed(str : String) : Nil
      feed(str.to_slice)
    end

    # --- assertions / readout ---

    # The visible text of row *y* (continuation cells contribute nothing).
    def row_text(y : Int32) : String
      return "" unless (0...@rows).includes?(y)
      String.build { |io| @grid[y].each { |cell| io << cell.grapheme unless cell.continuation? } }
    end

    # Whole screen as text, one row per line (trailing blanks stripped per line).
    def to_s(io : IO) : Nil
      @rows.times do |y|
        io << row_text(y).rstrip
        io << '\n' unless y == @rows - 1
      end
    end

    # True if *pattern* appears anywhere on screen (row-wise match).
    def includes?(pattern : String | Regex) : Bool
      !locate(pattern).nil?
    end

    # First {x, y} where *pattern* starts, or nil. For strings, x is the column;
    # for regexes, x is the match start column within the row.
    def locate(pattern : String | Regex) : {Int32, Int32}?
      @rows.times do |y|
        line = row_text(y)
        case pattern
        in String
          if idx = line.index(pattern)
            return {idx, y}
          end
        in Regex
          if match = pattern.match(line)
            return {match.begin || 0, y}
          end
        end
      end
      nil
    end

    # Cell at (x, y). Raises `IndexError` if out of bounds.
    def cell(x : Int32, y : Int32) : Cell
      unless (0...@cols).includes?(x) && (0...@rows).includes?(y)
        raise IndexError.new("cell (#{x}, #{y}) out of bounds for #{@cols}x#{@rows} screen")
      end
      @grid[y][x]
    end

    # A deterministic snapshot capturing the glyph grid AND per-cell style
    # (fg/bg/attr), run-length compressed — richer than glyph-only snapshots, so
    # color/attribute regressions are caught. *mask* blanks volatile regions
    # (matched against each row's text) at the cell level, so animated screens
    # snapshot deterministically.
    def to_styled_s(mask : Array(Regex) = [] of Regex) : String
      masked = compute_masked(mask)
      glyphs = glyph_grid(masked)
      styles = style_lines(masked)
      styles.empty? ? glyphs : "#{glyphs}\n\n# styles\n#{styles}"
    end

    # Marks the cells whose row-text matches any mask pattern.
    private def compute_masked(mask : Array(Regex)) : Array(Array(Bool))
      masked = Array.new(@rows) { Array.new(@cols, false) }
      return masked if mask.empty?

      @rows.times do |y|
        cols = [] of Int32
        text = String.build do |io|
          x = 0
          while x < @cols
            current = @grid[y][x]
            unless current.continuation?
              current.grapheme.each_char do |char|
                io << char
                cols << x
              end
            end
            x += 1
          end
        end

        mask.each do |regex|
          text.scan(regex) do |match|
            from = match.begin(0)
            next unless from
            (from...(from + match[0].size)).each do |i|
              col = cols[i]?
              masked[y][col] = true if col
            end
          end
        end
      end

      masked
    end

    private def glyph_grid(masked : Array(Array(Bool))) : String
      String.build do |io|
        @rows.times do |y|
          line = String.build do |lio|
            x = 0
            while x < @cols
              current = @grid[y][x]
              lio << (masked[y][x] ? " " : current.grapheme) unless current.continuation?
              x += 1
            end
          end
          io << line.rstrip
          io << '\n' unless y == @rows - 1
        end
      end
    end

    # Run-length list of styled spans: `r{row} c{col[-col]} "text" fg=… bg=… attr=…`.
    private def style_lines(masked : Array(Array(Bool))) : String
      String.build do |io|
        @rows.times do |y|
          x = 0
          while x < @cols
            current = @grid[y][x]
            if current.continuation? || masked[y][x] || !styled?(current)
              x += 1
              next
            end
            key = style_key(current)
            start = x
            text, x = read_styled_run(masked, y, x, key)
            range = (x - 1) > start ? "#{start}-#{x - 1}" : start.to_s
            io << "r#{y} c#{range} #{text.inspect} #{key}\n"
          end
        end
      end
    end

    # Consumes a maximal run of consecutive cells on row *y* sharing style *key*,
    # returning the run's text and the next column to scan.
    private def read_styled_run(masked : Array(Array(Bool)), y : Int32, x : Int32, key : String) : {String, Int32}
      text = String.build do |tio|
        while x < @cols
          run_cell = @grid[y][x]
          if run_cell.continuation?
            x += 1
            next
          end
          break if masked[y][x] || !styled?(run_cell) || style_key(run_cell) != key
          tio << run_cell.grapheme
          x += 1
        end
      end
      {text, x}
    end

    # A cell carries reportable style when it shows a non-blank glyph in a color
    # other than plain default/white, or has a background or attribute set.
    private def styled?(cell : Cell) : Bool
      return false if cell.grapheme == " "
      cell.bg != Color.default ||
        !cell.attr.none? ||
        (cell.fg != Color.default && cell.fg != Color.white)
    end

    private def style_key(cell : Cell) : String
      "fg=#{color_name(cell.fg)} bg=#{color_name(cell.bg)} attr=#{cell.attr.to_s.gsub(" | ", "|")}"
    end

    private def color_name(color : Color) : String
      return "default" if color == Color.default
      case color.mode
      when .ansi8?   then "ansi8(#{color.index})"
      when .ansi256? then "ansi256(#{color.index})"
      else                "rgb(#{color.r},#{color.g},#{color.b})"
      end
    end

    # --- parser ---

    private def consume(b : UInt8) : Nil
      case @state
      when State::Ground  then ground(b)
      when State::Escape  then escape(b)
      when State::Csi     then csi(b)
      when State::Osc     then osc(b)
      when State::OscEsc  then osc_esc(b)
      when State::Charset then @state = State::Ground # designate byte, ignored
      end
    end

    private def ground(b : UInt8) : Nil
      return continue_utf8(b) if @utf8_need > 0
      dispatch_ground(b)
    end

    # Accumulate a continuation byte of a multi-byte UTF-8 codepoint.
    private def continue_utf8(b : UInt8) : Nil
      if (b & 0xC0) == 0x80
        @utf8 << b
        @utf8_need -= 1
        flush_utf8 if @utf8_need == 0
      else
        # malformed sequence: drop it and reprocess this byte fresh
        @utf8.clear
        @utf8_need = 0
        dispatch_ground(b)
      end
    end

    private def dispatch_ground(b : UInt8) : Nil
      case b
      when 0x1B    then @state = State::Escape
      when 0x0D    then @cursor_x = 0
      when 0x0A    then line_feed
      when 0x08    then @cursor_x = clamp_x(@cursor_x - 1)
      when 0x09    then tab
      when .< 0x20 then nil # other C0 controls ignored
      when .< 0x80 then put_grapheme(b.unsafe_chr.to_s)
      else              begin_utf8(b)
      end
    end

    private def begin_utf8(b : UInt8) : Nil
      need = utf8_len(b) - 1
      if need <= 0
        put_grapheme(String.new(Bytes[b]))
      else
        @utf8 = [b]
        @utf8_need = need
      end
    end

    private def flush_utf8 : Nil
      put_grapheme(String.new(Slice.new(@utf8.to_unsafe, @utf8.size)))
      @utf8.clear
    end

    private def utf8_len(lead : UInt8) : Int32
      return 1 if lead < 0x80
      return 2 if (lead & 0xE0) == 0xC0
      return 3 if (lead & 0xF0) == 0xE0
      return 4 if (lead & 0xF8) == 0xF0
      1
    end

    private def escape(b : UInt8) : Nil
      case b.unsafe_chr
      when '['                then start_csi
      when ']'                then @state = State::Osc
      when '(', ')', '*', '+' then @state = State::Charset
      when 'P', 'X', '^', '_' then @state = State::Osc    # DCS/SOS/PM/APC: consume like a string
      else                         @state = State::Ground # ESC =, ESC >, ESC M, etc. ignored
      end
    end

    private def start_csi : Nil
      @state = State::Csi
      @params.clear
      @cur_param = nil
      @csi_prefix = nil
      @csi_intermediate = nil
    end

    private def csi(b : UInt8) : Nil
      ch = b.unsafe_chr
      case b
      when 0x30..0x39 # 0-9
        @cur_param = (@cur_param || 0) * 10 + (b - 0x30)
      when 0x3B, 0x3A # ; or : (treat sub-param separator as ;)
        @params << (@cur_param || 0)
        @cur_param = nil
      when 0x3C, 0x3D, 0x3E, 0x3F # < = > ? private prefix (first char only)
        @csi_prefix = ch
      when 0x20..0x2F # intermediate bytes
        @csi_intermediate = ch
      when 0x40..0x7E # final byte
        @params << (@cur_param || 0) unless @cur_param.nil?
        dispatch_csi(ch)
        @state = State::Ground
      else
        @state = State::Ground
      end
    end

    private def osc(b : UInt8) : Nil
      case b
      when 0x07 then @state = State::Ground # BEL terminates
      when 0x1B then @state = State::OscEsc
      else           nil # consume body
      end
    end

    private def osc_esc(b : UInt8) : Nil
      # Expect '\' to complete an ST (ESC \); anything else, just return to ground.
      @state = State::Ground
    end

    # --- CSI dispatch ---

    private def dispatch_csi(final : Char) : Nil
      if @csi_prefix
        dispatch_private(final)
        return
      end

      case final
      when 'H', 'f', 'A', 'B', 'C', 'D', 'G', 'd' then move_cursor(final)
      when 'J'                                    then erase_display(@params[0]? || 0)
      when 'K'                                    then erase_line(@params[0]? || 0)
      when 'X'                                    then erase_chars(param_count(0))
      when 'm'                                    then apply_sgr
      end
    end

    private def move_cursor(final : Char) : Nil
      case final
      when 'H', 'f'
        @cursor_y = clamp_y(param_pos(0) - 1)
        @cursor_x = clamp_x(param_pos(1) - 1)
      when 'A' then @cursor_y = clamp_y(@cursor_y - param_count(0))
      when 'B' then @cursor_y = clamp_y(@cursor_y + param_count(0))
      when 'C' then @cursor_x = clamp_x(@cursor_x + param_count(0))
      when 'D' then @cursor_x = clamp_x(@cursor_x - param_count(0))
      when 'G' then @cursor_x = clamp_x(param_pos(0) - 1) # CHA / HPA
      when 'd' then @cursor_y = clamp_y(param_pos(0) - 1) # VPA
      end
    end

    private def dispatch_private(final : Char) : Nil
      return unless @csi_prefix == '?'
      return unless final == 'h' || final == 'l'
      set = (final == 'h')
      @params.each do |mode|
        case mode
        when   25 then @cursor_visible = set
        when 1049 then clear_all if set # enter/exit alternate screen → fresh grid
        end
        # 2026 (sync), 1000/1006 (mouse), 12 (blink), etc. recognized & ignored.
      end
    end

    # CUP/CHA/VPA positional param: missing or 0 means 1.
    private def param_pos(i : Int32) : Int32
      v = @params[i]? || 0
      v == 0 ? 1 : v
    end

    # Movement count: missing or 0 means 1.
    private def param_count(i : Int32) : Int32
      v = @params[i]? || 0
      v == 0 ? 1 : v
    end

    # --- SGR (colors / attributes) ---

    private def apply_sgr : Nil
      params = @params.empty? ? [0] : @params
      i = 0
      while i < params.size
        i = apply_sgr_at(params, i)
      end
    end

    private def apply_sgr_at(params : Array(Int32), i : Int32) : Int32
      code = params[i]
      case code
      when 0                then reset_pen
      when 1..9             then @pen_attr |= attr_for(code)
      when 22               then @pen_attr &= ~(Attribute::Bold | Attribute::Dim)
      when 23..29           then @pen_attr &= ~attr_for(code - 20)
      when 30..39, 90..97   then return apply_fg(params, i)
      when 40..49, 100..107 then return apply_bg(params, i)
      end
      i + 1
    end

    private def reset_pen : Nil
      @pen_fg = Color.default
      @pen_bg = Color.default
      @pen_attr = Attribute::None
    end

    private def attr_for(code : Int32) : Attribute
      case code
      when 1 then Attribute::Bold
      when 2 then Attribute::Dim
      when 3 then Attribute::Italic
      when 4 then Attribute::Underline
      when 5 then Attribute::Blink
      when 7 then Attribute::Reverse
      when 8 then Attribute::Hidden
      when 9 then Attribute::Strikethrough
      else        Attribute::None
      end
    end

    private def apply_fg(params : Array(Int32), i : Int32) : Int32
      code = params[i]
      case code
      when 38     then return consume_extended_color(params, i, fg: true)
      when 39     then @pen_fg = Color.default
      when 90..97 then @pen_fg = Color.ansi256(code - 90 + 8)
      else             @pen_fg = Color.ansi8(code - 30) # 30..37
      end
      i + 1
    end

    private def apply_bg(params : Array(Int32), i : Int32) : Int32
      code = params[i]
      case code
      when 48       then return consume_extended_color(params, i, fg: false)
      when 49       then @pen_bg = Color.default
      when 100..107 then @pen_bg = Color.ansi256(code - 100 + 8)
      else               @pen_bg = Color.ansi8(code - 40) # 40..47
      end
      i + 1
    end

    # Handles 38/48 ;5;n (ansi256) and ;2;r;g;b (rgb). Returns the index past the
    # consumed params.
    private def consume_extended_color(params : Array(Int32), i : Int32, *, fg : Bool) : Int32
      case params[i + 1]?
      when 5
        if idx = params[i + 2]?
          assign_color(Color.ansi256(idx), fg)
        end
        i + 3
      when 2
        r = params[i + 2]? || 0
        g = params[i + 3]? || 0
        b = params[i + 4]? || 0
        assign_color(Color.rgb(r, g, b), fg)
        i + 5
      else
        i + 1
      end
    end

    private def assign_color(color : Color, fg : Bool) : Nil
      fg ? (@pen_fg = color) : (@pen_bg = color)
    end

    # --- grid mutation ---

    private def put_grapheme(s : String) : Nil
      width = Termisu::UnicodeWidth.grapheme_width(s)
      return if width == 0 # combining marks: skip (Phase 1)

      if @cursor_x >= @cols
        @cursor_x = 0
        line_feed
      end

      @grid[@cursor_y][@cursor_x] = Cell.new(s, fg: @pen_fg, bg: @pen_bg, attr: @pen_attr)
      if width == 2
        @grid[@cursor_y][@cursor_x + 1] = Cell.continuation if @cursor_x + 1 < @cols
        @cursor_x += 2
      else
        @cursor_x += 1
      end
      @cursor_x = @cols if @cursor_x > @cols # allow "pending wrap" position
    end

    private def line_feed : Nil
      # No scroll region handling: clamp at bottom (Termisu uses absolute moves).
      @cursor_y += 1 if @cursor_y < @rows - 1
    end

    private def tab : Nil
      @cursor_x = clamp_x(((@cursor_x // 8) + 1) * 8)
    end

    private def erase_display(mode : Int32) : Nil
      case mode
      when 0 # cursor to end of screen
        erase_in_line(@cursor_y, @cursor_x, @cols)
        ((@cursor_y + 1)...@rows).each { |y| clear_row(y) }
      when 1 # start to cursor
        (0...@cursor_y).each { |y| clear_row(y) }
        erase_in_line(@cursor_y, 0, @cursor_x + 1)
      else # 2 / 3: whole screen
        clear_all
      end
    end

    private def erase_line(mode : Int32) : Nil
      case mode
      when 0 then erase_in_line(@cursor_y, @cursor_x, @cols)
      when 1 then erase_in_line(@cursor_y, 0, @cursor_x + 1)
      else        erase_in_line(@cursor_y, 0, @cols)
      end
    end

    private def erase_chars(n : Int32) : Nil
      erase_in_line(@cursor_y, @cursor_x, {@cols, @cursor_x + n}.min)
    end

    private def erase_in_line(y : Int32, from_x : Int32, to_x : Int32) : Nil
      return unless (0...@rows).includes?(y)
      (from_x...to_x).each { |x| @grid[y][x] = Cell.default if (0...@cols).includes?(x) }
    end

    private def clear_row(y : Int32) : Nil
      @grid[y] = Array.new(@cols) { Cell.default }
    end

    private def clear_all : Nil
      @rows.times { |y| clear_row(y) }
      @cursor_x = 0
      @cursor_y = 0
    end

    private def clamp_x(x : Int32) : Int32
      x.clamp(0, @cols - 1)
    end

    private def clamp_y(y : Int32) : Int32
      y.clamp(0, @rows - 1)
    end
  end
end
