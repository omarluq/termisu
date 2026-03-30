enum Termisu::Terminal::Mode
  def raw? : Bool
    self == self.class.raw
  end
end

# Terminal subclass that captures all writes for verification.
#
# Useful for testing Terminal output including escape sequences
# like BSU/ESU for synchronized updates.
#
# Example:
# ```
# terminal = CaptureTerminal.new(sync_updates: true)
# terminal.set_cell(0, 0, 'X')
# terminal.render
# terminal.output.should contain(Termisu::Terminal::BSU)
# ```
class CaptureTerminal < Termisu::Terminal
  property writes : Array(String) = [] of String
  property captured_flush_count : Int32 = 0
  property size = {80, 24}

  @fake_raw_mode : Bool = false
  @fake_current_mode : Termisu::Terminal::Mode? = nil
  @fake_infd : Int32 = 0
  @fake_outfd : Int32 = 1
  @closed : Bool = false

  def initialize(*, sync_updates : Bool = true)
    super(sync_updates: sync_updates)
  end

  def write(data : String)
    @writes << data
    # Don't call super - we don't want to write to real TTY
  end

  def flush
    @captured_flush_count += 1
    # Don't call super - we don't want to flush real TTY
  end

  def infd : Int32
    @fake_infd
  end

  def outfd : Int32
    @fake_outfd
  end

  def enable_raw_mode
    @fake_raw_mode = true
    @fake_current_mode = Termisu::Terminal::Mode.raw
  end

  def disable_raw_mode
    @fake_raw_mode = false
    @fake_current_mode = nil
  end

  def raw_mode? : Bool
    @fake_raw_mode
  end

  def with_raw_mode(&)
    previous = @fake_current_mode
    enable_raw_mode
    yield
  ensure
    if previous.nil?
      disable_raw_mode
    else
      self.mode = previous
    end
  end

  def current_mode : Termisu::Terminal::Mode?
    @fake_current_mode
  end

  def mode=(mode : Termisu::Terminal::Mode)
    @fake_current_mode = mode
    @fake_raw_mode = mode.raw?
  end

  def with_mode(mode : Termisu::Terminal::Mode, preserve_screen : Bool = false, &)
    user_interactive = mode.canonical? || mode.echo?
    was_in_alternate = @alternate_screen

    backup_cursor = @cursor
    @cursor = Cursor.new visible: true
    apply_cursor_state

    exit_alternate_screen if !preserve_screen && user_interactive && was_in_alternate

    previous = @fake_current_mode
    self.mode = mode
    yield
  ensure
    self.mode = previous || Termisu::Terminal::Mode.raw

    if was_in_alternate && !@alternate_screen
      enter_alternate_screen
    end

    @cursor = backup_cursor unless backup_cursor.nil?
    apply_cursor_state
    apply_terminal_state
    invalidate_buffer unless mode.none?
    reset_render_state
    flush
  end

  def close
    return if @closed

    @closed = true
    disable_mouse
    disable_enhanced_keyboard
    exit_alternate_screen
    disable_raw_mode
  end

  def closed? : Bool
    @closed
  end

  def output : String
    @writes.join
  end

  def clear_captured
    @writes.clear
    @captured_flush_count = 0
  end
end
