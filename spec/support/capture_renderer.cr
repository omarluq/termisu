# Renderer with caching behavior for testing state management.
#
# Unlike MockRenderer which just tracks calls, CaptureRenderer actually
# implements caching logic similar to Terminal, making it suitable for
# testing caching behavior and escape sequence output.
#
# Example:
# ```
# renderer = CaptureRenderer.new
# renderer.foreground = Termisu::Color.red
# renderer.foreground = Termisu::Color.red # No-op due to caching
# renderer.writes.size.should eq(1)
# ```
class CaptureRenderer < Termisu::Renderer
  property writes : Array(String) = [] of String
  property flush_count : Int32 = 0

  # Cached render state (mirrors Terminal behavior)
  @cached_fg : Termisu::Color?
  @cached_bg : Termisu::Color?
  @cached_attr : Termisu::Attribute = Termisu::Attribute::None
  @cached_cursor_visible : Bool?

  def initialize
    @cached_fg = nil
    @cached_bg = nil
    @cached_attr = Termisu::Attribute::None
    @cached_cursor_visible = nil
  end

  # --- Core I/O ---

  def write(data : String)
    @writes << data
  end

  def flush
    @flush_count += 1
  end

  def size : {Int32, Int32}
    {80, 24}
  end

  def close; end

  # --- Cursor Control ---

  def move_cursor(x : Int32, y : Int32)
    write("\e[#{y + 1};#{x + 1}H")
  end

  def write_show_cursor
    return if @cached_cursor_visible
    @cached_cursor_visible = true
    write("\e[?25h")
  end

  def write_hide_cursor
    cached = @cached_cursor_visible
    return if cached.is_a?(Bool) && !cached
    @cached_cursor_visible = false
    write("\e[?25l")
  end

  # --- Color Control (with caching) ---

  def foreground=(color : Termisu::Color)
    return if @cached_fg == color
    @cached_fg = color

    if color.default?
      write("\e[39m")
    else
      case color.mode
      when .ansi8?
        write("\e[3#{color.index}m")
      when .ansi256?
        write("\e[38;5;#{color.index}m")
      when .rgb?
        write("\e[38;2;#{color.r};#{color.g};#{color.b}m")
      end
    end
  end

  def background=(color : Termisu::Color)
    return if @cached_bg == color
    @cached_bg = color

    if color.default?
      write("\e[49m")
    else
      case color.mode
      when .ansi8?
        write("\e[4#{color.index}m")
      when .ansi256?
        write("\e[48;5;#{color.index}m")
      when .rgb?
        write("\e[48;2;#{color.r};#{color.g};#{color.b}m")
      end
    end
  end

  # --- Text Attributes (with caching) ---

  def reset_attributes
    write("\e[0m")
    @cached_fg = nil
    @cached_bg = nil
    @cached_attr = Termisu::Attribute::None
  end

  def enable_bold
    return if @cached_attr.bold?
    @cached_attr |= Termisu::Attribute::Bold
    write("\e[1m")
  end

  def enable_underline
    return if @cached_attr.underline?
    @cached_attr |= Termisu::Attribute::Underline
    write("\e[4m")
  end

  def enable_blink
    return if @cached_attr.blink?
    @cached_attr |= Termisu::Attribute::Blink
    write("\e[5m")
  end

  def enable_reverse
    return if @cached_attr.reverse?
    @cached_attr |= Termisu::Attribute::Reverse
    write("\e[7m")
  end

  def enable_dim
    return if @cached_attr.dim?
    @cached_attr |= Termisu::Attribute::Dim
    write("\e[2m")
  end

  def enable_cursive
    return if @cached_attr.cursive?
    @cached_attr |= Termisu::Attribute::Cursive
    write("\e[3m")
  end

  def enable_hidden
    return if @cached_attr.hidden?
    @cached_attr |= Termisu::Attribute::Hidden
    write("\e[8m")
  end

  def enable_strikethrough
    return if @cached_attr.strikethrough?
    @cached_attr |= Termisu::Attribute::Strikethrough
    write("\e[9m")
  end

  # --- Test Helpers ---

  # Resets cached state (forces next calls to emit sequences).
  def reset_render_state
    @cached_fg = nil
    @cached_bg = nil
    @cached_attr = Termisu::Attribute::None
    @cached_cursor_visible = nil
  end

  # Clears captured writes.
  def clear_writes
    @writes.clear
  end

  # Returns number of writes captured.
  def write_count : Int32
    @writes.size
  end
end
