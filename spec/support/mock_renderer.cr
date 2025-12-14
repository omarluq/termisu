# Comprehensive mock renderer that tracks all method calls.
#
# Suitable for testing Buffer, RenderState, and any component that uses Renderer.
# All method calls are tracked via counters and arrays for verification.
#
# Example:
# ```
# renderer = MockRenderer.new
# renderer.foreground = Termisu::Color.red
# renderer.fg_calls.should eq([Termisu::Color.red])
# ```
class MockRenderer < Termisu::Renderer
  # Tracked method calls
  property write_calls : Array(String) = [] of String
  property move_calls : Array({Int32, Int32}) = [] of {Int32, Int32}
  property fg_calls : Array(Termisu::Color) = [] of Termisu::Color
  property bg_calls : Array(Termisu::Color) = [] of Termisu::Color

  # Method call counters
  property flush_count : Int32 = 0
  property close_count : Int32 = 0
  property reset_count : Int32 = 0
  property show_cursor_count : Int32 = 0
  property hide_cursor_count : Int32 = 0

  # Attribute counters
  property bold_count : Int32 = 0
  property underline_count : Int32 = 0
  property reverse_count : Int32 = 0
  property blink_count : Int32 = 0
  property dim_count : Int32 = 0
  property cursive_count : Int32 = 0
  property hidden_count : Int32 = 0
  property strikethrough_count : Int32 = 0

  # Configurable size
  property mock_size : {Int32, Int32} = {80, 24}

  # --- Core I/O ---

  def write(data : String)
    @write_calls << data
  end

  def flush
    @flush_count += 1
  end

  def size : {Int32, Int32}
    @mock_size
  end

  def close
    @close_count += 1
  end

  # --- Cursor Control ---

  def move_cursor(x : Int32, y : Int32)
    @move_calls << {x, y}
  end

  def write_show_cursor
    @show_cursor_count += 1
  end

  def write_hide_cursor
    @hide_cursor_count += 1
  end

  # --- Color Control ---

  def foreground=(color : Termisu::Color)
    @fg_calls << color
  end

  def background=(color : Termisu::Color)
    @bg_calls << color
  end

  # --- Text Attributes ---

  def reset_attributes
    @reset_count += 1
  end

  def enable_bold
    @bold_count += 1
  end

  def enable_underline
    @underline_count += 1
  end

  def enable_reverse
    @reverse_count += 1
  end

  def enable_blink
    @blink_count += 1
  end

  def enable_dim
    @dim_count += 1
  end

  def enable_cursive
    @cursive_count += 1
  end

  def enable_hidden
    @hidden_count += 1
  end

  def enable_strikethrough
    @strikethrough_count += 1
  end

  # --- Test Helpers ---

  # Clears all tracked calls and resets counters.
  def clear
    @write_calls.clear
    @move_calls.clear
    @fg_calls.clear
    @bg_calls.clear
    @flush_count = 0
    @close_count = 0
    @reset_count = 0
    @show_cursor_count = 0
    @hide_cursor_count = 0
    @bold_count = 0
    @underline_count = 0
    @reverse_count = 0
    @blink_count = 0
    @dim_count = 0
    @cursive_count = 0
    @hidden_count = 0
    @strikethrough_count = 0
  end
end
