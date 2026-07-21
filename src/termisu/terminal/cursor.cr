class Termisu::Terminal
  struct Cursor
    property x : Int32 = 0
    property y : Int32 = 0
    property? visible : Bool
    property? blink : Bool = false
    property shape : Shape = Shape::Block

    def initialize(@visible = false)
    end

    enum Shape
      Block     = 1
      Underline = 3
      Bar       = 5
    end
  end

  private def apply_cursor_state
    x, y = @cursor.x, @cursor.y
    @cursor.x, @cursor.y = -1, -1
    move_cursor(x, y)

    if @cursor.visible?
      @cursor.visible = false
      show_cursor
    else
      @cursor.visible = true
      hide_cursor
    end
  end

  def hide_cursor
    return unless @cursor.visible?
    write(@terminfo.hide_cursor_seq)
    @cursor.visible = false
  end

  def show_cursor
    return if @cursor.visible?
    write(@terminfo.show_cursor_seq)
    @cursor.visible = true
    write_cursor
  end

  def enable_cursor_blink
    return if @cursor.blink?
    @cursor.blink = true
    write_cursor
  end

  def disable_cursor_blink
    return unless @cursor.blink?
    @cursor.blink = false
    write_cursor
  end

  def cursor_shape=(shape : Cursor::Shape)
    return shape if @cursor.shape == shape
    @cursor.shape = shape
    write_cursor
    shape
  end

  private def write_cursor
    return unless @cursor.visible?

    # DECSCUSR carries the preferred cursor shape+blink state, while cvvis is
    # sent as a compatibility shim for terminals that still honor the legacy
    # terminfo blink capability. tmux, Alacritty, and Neovim can treat these
    # sequences differently, so keep both for now and re-check behavior before
    # dropping the terminfo path.
    # Follow-up: validate cursor shape/blink behavior across supported
    # terminals and remove blink_cursor_seq when DECSCUSR support is reliable.
    write("\e[#{@cursor.shape.value + (@cursor.blink? ? 0 : 1)} q")
    write(@terminfo.blink_cursor_seq) if @cursor.blink?
  end

  def move_cursor(
    x : Int32 = @cursor.x,
    y : Int32 = @cursor.y,
  )
    width, height = size
    return if width <= 0 || height <= 0

    x = x.clamp(0, width - 1)
    y = y.clamp(0, height - 1)

    return if x == @cursor.x && y == @cursor.y

    if @terminfo.cup_is_standard?
      write_cup_direct(x, y)
    else
      seq = @terminfo.cursor_position_seq(y, x)
      if seq.empty?
        write("\e[#{y + 1};#{x + 1}H")
      else
        write(seq)
      end
    end

    @cursor.x, @cursor.y = x, y
  end

  # Streams the standard CSI cursor-position sequence through the scratch
  # buffer (byte-identical to cursor_position_seq output) so per-move String
  # allocation is avoided on the rendering hot path.
  private def write_cup_direct(x : Int32, y : Int32) : Nil
    buf = @seq_buffer
    buf.clear
    buf << "\e["
    append_decimal(buf, y + 1)
    buf.write_byte 0x3B_u8 # ';'
    append_decimal(buf, x + 1)
    buf.write_byte 0x48_u8 # 'H'
    write(buf.to_slice)
  end

  # Coordinates are 1-based and clamped to the terminal size, so values
  # beyond the DECIMAL table only occur on very large terminals.
  private def append_decimal(buf : IO::Memory, value : Int32) : Nil
    if 0 <= value < 256
      buf << DECIMAL[value]
    else
      value.to_s(buf)
    end
  end

  private def with_ephemeral_cursor(visible : Bool = false, &)
    cursor_backup = @cursor
    @cursor = Cursor.new visible
    apply_cursor_state
    begin
      yield
    ensure
      @cursor = cursor_backup
      apply_cursor_state
    end
  end

  # Write *data* to the terminal. Use *columns_advanced* to specify how
  # much this will move the cursor to the right. If this would move the
  # cursor beyond the terminal's width, it will wrap into the next line
  def write(data : String, columns_advanced = 0)
    @backend.write(data)
    advance_cursor(columns_advanced)
  end

  # Byte overload of `write` for pre-composed escape sequences and batch
  # content; streams to the backend without materializing a String.
  def write(data : Bytes, columns_advanced = 0)
    @backend.write(data)
    advance_cursor(columns_advanced)
  end

  private def advance_cursor(columns_advanced : Int32) : Nil
    # Skipping the wrap arithmetic assumes @cursor.x < width, which holds
    # except transiently after a shrink-resize before the next move_cursor.
    return if columns_advanced == 0

    width, height = size
    return if width <= 0 || height <= 0

    x = @cursor.x + columns_advanced

    @cursor.x = x % width
    @cursor.y = (@cursor.y + x // width).clamp(0, height - 1)
  end
end
