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

    seq = @terminfo.cursor_position_seq(y, x)
    if seq.empty?
      write("\e[#{y + 1};#{x + 1}H")
    else
      write(seq)
    end

    @cursor.x, @cursor.y = x, y
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

    width, height = size
    return if width <= 0 || height <= 0

    x = @cursor.x + columns_advanced

    @cursor.x = x % width
    @cursor.y = (@cursor.y + x // width).clamp(0, height - 1)
  end
end
