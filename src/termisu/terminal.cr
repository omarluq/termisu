# High-level terminal interface combining I/O backend, Terminfo, and cell buffer.
#
# Provides a complete terminal UI API including:
# - Cell-based rendering with double buffering
# - Cursor movement and visibility
# - Colors and text attributes
# - Alternate screen mode
#
# Example:
# ```
# terminal = Termisu::Terminal.new
# terminal.enable_raw_mode
# terminal.enter_alternate_screen
#
# terminal.set_cell(10, 5, 'H', fg: Color.red)
# terminal.set_cell(11, 5, 'i', fg: Color.green)
# terminal.set_cursor(12, 5)
# terminal.render
#
# terminal.close
# ```
class Termisu::Terminal < Termisu::Renderer
  Log = Termisu::Logs::Terminal
  @backend : Terminal::Backend
  @terminfo : Terminfo
  @buffer : Buffer
  @alternate_screen : Bool = false
  @mouse_enabled : Bool = false
  @enhanced_keyboard : Bool = false
  @bracketed_paste : Bool = false
  @sync_updates : Bool = true
  @terminal_closed = Atomic(Bool).new(false)

  # A clean buffer may skip frame control bytes only while its requested cursor
  # state still matches the state established by a successful render.
  @established_cursor : Cursor?
  @buffer_may_be_dirty : Bool = false
  getter cursor : Cursor = Cursor.new
  getter title : String = ""

  # Cached render state for direct API optimization.
  # Prevents redundant escape sequences when the same style is set repeatedly.
  @cached_fg : Color?
  @cached_bg : Color?
  @cached_attr : Attribute = Attribute::None
  @cached_attr_known : Bool = true

  # Cached terminal size to avoid a TIOCGWINSZ ioctl per write/move_cursor.
  # Refreshed by resize() and invalidated after mode switches.
  @cached_size : {Int32, Int32}?

  # Reusable scratch buffer for composed escape sequences (combined SGR,
  # RGB colors, cursor moves). Composing here and writing the slice avoids
  # a String allocation per sequence. Never used reentrantly: each composer
  # fills and writes it before returning, and rendering is single-fiber.
  @seq_buffer = IO::Memory.new(64)

  # Creates a new terminal.
  #
  # Parameters:
  # - `backend` - Terminal::Backend instance for I/O operations (default: Terminal::Backend.new)
  # - `terminfo` - Terminfo instance for capability strings (default: Terminfo.new)
  # - `sync_updates` - Enable DEC mode 2026 synchronized updates (default: true)
  def initialize(
    backend : Terminal::Backend? = nil,
    terminfo : Terminfo? = nil,
    *,
    @sync_updates : Bool = true,
  )
    @backend = backend || Terminal::Backend.new
    @terminfo = terminfo || build_terminfo
    @buffer = build_buffer
    lifecycle_log do
      Log.debug { "Terminal initialized: #{@buffer.width}x#{@buffer.height}, sync_updates: #{@sync_updates}" }
    end
  end

  private def build_terminfo : Terminfo
    Terminfo.new
  rescue error
    close_backend_after_initialization_failure(error)
  end

  private def build_buffer : Buffer
    width, height = size
    Buffer.new(width, height)
  rescue error
    close_backend_after_initialization_failure(error)
  end

  private def close_backend_after_initialization_failure(error : Exception) : NoReturn
    @backend.close rescue nil
    raise error
  end

  # Enters alternate screen mode.
  #
  # Switches to alternate screen buffer, clears the screen,
  # enters keypad mode, and hides cursor. Also resets cached
  # render state since we're entering a fresh screen.
  def enter_alternate_screen
    return if @alternate_screen
    lifecycle_log { Log.debug { "Entering alternate screen" } }

    # Record the transition before emitting anything so a partial write is
    # always paired with a best-effort exit during rollback.
    @alternate_screen = true
    begin
      write(@terminfo.enter_ca_seq)
      write(@terminfo.clear_screen_seq)
      write(@terminfo.enter_keypad_seq)
      reset_render_state
      apply_cursor_state
      flush
    rescue ex
      exit_alternate_screen rescue nil
      raise ex
    end
  end

  # Exits alternate screen mode.
  #
  # Shows cursor, exits keypad mode, and returns to main screen buffer.
  # Also resets cached render state since we're returning to the
  # main screen which may have different state.
  def exit_alternate_screen
    return unless @alternate_screen
    lifecycle_log { Log.debug { "Exiting alternate screen" } }

    # Clear first so shutdown is exactly-once even when output fails. Continue
    # through every restoration step and report the first error afterwards.
    @alternate_screen = false
    @cursor = Cursor.new visible: true
    error = capture_cleanup_error(nil) { apply_cursor_state }
    error = capture_cleanup_error(error) { write(@terminfo.exit_keypad_seq) }
    error = capture_cleanup_error(error) { write(@terminfo.exit_ca_seq) }
    reset_render_state
    error = capture_cleanup_error(error) { flush }
    raise error if error
  end

  # Returns whether alternate screen mode is active.
  def alternate_screen? : Bool
    @alternate_screen
  end

  # Clears the screen.
  #
  # Writes the clear screen escape sequence immediately and flushes.
  # Also resets cached render state since screen content is cleared.
  def clear_screen
    Log.debug { "Clearing screen" }
    write(@terminfo.clear_screen_seq)
    reset_render_state
    flush
  end

  # Resets the cached render state.
  #
  # Call this when the terminal state becomes unknown (e.g., after external
  # programs have modified the terminal, or after errors). This forces
  # the next color/attribute calls to emit escape sequences even if
  # the cached values match.
  #
  # The following operations automatically reset render state:
  # - enter_alternate_screen
  # - exit_alternate_screen
  # - clear_screen
  # - reset_attributes
  def reset_render_state
    @cached_fg = nil
    @cached_bg = nil
    @cached_attr = Attribute::None
    @cached_attr_known = false
    @established_cursor = nil
  end

  # Precomputed SGR color sequences, indexed by color index.
  # Entries MUST remain byte-identical to the former string interpolations.
  # Indices are provably in range: color.default? is handled before the
  # table lookup, and Color::Validator restricts ansi8 to -1..7 and
  # ansi256 to -1..255 at construction.
  private FG_ANSI8   = Array(String).new(8) { |i| "\e[3#{i}m" }
  private BG_ANSI8   = Array(String).new(8) { |i| "\e[4#{i}m" }
  private FG_ANSI256 = Array(String).new(256) { |i| "\e[38;5;#{i}m" }
  private BG_ANSI256 = Array(String).new(256) { |i| "\e[48;5;#{i}m" }

  # Precomputed SGR parameter fragments (no CSI framing) for the combined
  # apply_sgr emitter, plus decimal images for RGB components and cursor
  # coordinates. Appending these is a memcpy — measured faster than
  # composing digits one at a time.
  private SGR_FG_ANSI8   = Array(String).new(8) { |i| "3#{i}" }
  private SGR_BG_ANSI8   = Array(String).new(8) { |i| "4#{i}" }
  private SGR_FG_ANSI256 = Array(String).new(256) { |i| "38;5;#{i}" }
  private SGR_BG_ANSI256 = Array(String).new(256) { |i| "48;5;#{i}" }
  private DECIMAL        = Array(String).new(256, &.to_s)

  # Sets the foreground color with full ANSI-8, ANSI-256, and RGB support.
  #
  # Caches the color to avoid redundant escape sequences when called
  # repeatedly with the same color.
  def foreground=(color : Color)
    ensure_style_state
    return if @cached_fg == color
    @cached_fg = color

    if color.default?
      write("\e[39m") # Default foreground
    else
      case color.mode
      when .ansi8?
        write(FG_ANSI8[color.index])
      when .ansi256?
        write(FG_ANSI256[color.index])
      when .rgb?
        write_rgb_sgr("\e[38;2;", color)
      end
    end
  end

  # Sets the background color with full ANSI-8, ANSI-256, and RGB support.
  #
  # Caches the color to avoid redundant escape sequences when called
  # repeatedly with the same color.
  def background=(color : Color)
    ensure_style_state
    return if @cached_bg == color
    @cached_bg = color

    if color.default?
      write("\e[49m") # Default background
    else
      case color.mode
      when .ansi8?
        write(BG_ANSI8[color.index])
      when .ansi256?
        write(BG_ANSI256[color.index])
      when .rgb?
        write_rgb_sgr("\e[48;2;", color)
      end
    end
  end

  # Composes a full true-color SGR sequence into the scratch buffer and
  # writes it as bytes, avoiding the former per-call String interpolation.
  private def write_rgb_sgr(intro : String, color : Color) : Nil
    buf = @seq_buffer
    buf.clear
    buf << intro
    buf << DECIMAL[color.r]
    buf.write_byte 0x3B_u8 # ';'
    buf << DECIMAL[color.g]
    buf.write_byte 0x3B_u8
    buf << DECIMAL[color.b]
    buf.write_byte 0x6D_u8 # 'm'
    write(buf.to_slice)
  end

  # Emits a full style transition as one combined SGR sequence
  # (`\e[p1;p2;...m`) instead of one write per granular change.
  #
  # The transition is computed against the terminal's own cached style, not
  # the caller's *old_* view: the cache also tracks direct API calls
  # (`foreground=`, `enable_bold`, ...), so it is at least as current —
  # mirroring how the granular setters have always consulted it.
  #
  # Attribute removal uses the ECMA-48 selective off codes
  # (22/23/24/25/27/28/29) so colors survive attribute drops without the
  # sgr0-plus-recolor round trip. SGR 22 clears both bold and dim, so
  # whichever of the two the target style retains is re-emitted after it.
  def apply_sgr(
    fg : Color,
    bg : Color,
    attr : Attribute,
    old_fg : Color?,
    old_bg : Color?,
    old_attr : Attribute,
  ) : Nil
    # `Attribute::None` cannot represent an unknown physical state. A failed
    # frame marks this cache unknown, so establish a real default before any
    # selective transition. This also invalidates both cached colors.
    ensure_style_state

    # The combined emitter hardcodes ECMA-48 SGR parameters; when the loaded
    # attribute capabilities are non-standard, defer to the granular
    # terminfo-driven decomposition (mirrors the cup_is_standard? guard).
    return super unless @terminfo.attrs_are_standard?

    cached_attr = @cached_attr
    removed = cached_attr & ~attr
    added = attr & ~cached_attr
    fg_changed = @cached_fg != fg
    bg_changed = @cached_bg != bg
    # Explicit None comparisons: the flags-generated `none?` predicate is
    # `includes?(None)`, which is vacuously true for every value.
    return if removed == Attribute::None && added == Attribute::None && !fg_changed && !bg_changed

    buf = @seq_buffer
    buf.clear
    buf << "\e["
    append_attr_params(buf, attr, cached_attr, removed, added)
    append_color_param(buf, fg, foreground: true) if fg_changed
    append_color_param(buf, bg, foreground: false) if bg_changed
    buf.write_byte 0x6D_u8 # 'm'
    write(buf.to_slice)

    @cached_attr = attr
    @cached_attr_known = true
    @cached_fg = fg
    @cached_bg = bg
  end

  # Appends attribute off/on SGR parameters for the transition to *attr*.
  #
  # The branch count is a flat per-attribute dispatch table, not nested logic.
  # ameba:disable Metrics/CyclomaticComplexity
  private def append_attr_params(
    buf : IO::Memory,
    attr : Attribute,
    cached_attr : Attribute,
    removed : Attribute,
    added : Attribute,
  ) : Nil
    intensity_off = removed.bold? || removed.dim?
    sgr_param(buf, "22") if intensity_off
    sgr_param(buf, "23") if removed.cursive?
    sgr_param(buf, "24") if removed.underline?
    sgr_param(buf, "25") if removed.blink?
    sgr_param(buf, "27") if removed.reverse?
    sgr_param(buf, "28") if removed.hidden?
    sgr_param(buf, "29") if removed.strikethrough?
    sgr_param(buf, "1") if attr.bold? && (intensity_off || !cached_attr.bold?)
    sgr_param(buf, "2") if attr.dim? && (intensity_off || !cached_attr.dim?)
    sgr_param(buf, "3") if added.cursive?
    sgr_param(buf, "4") if added.underline?
    sgr_param(buf, "5") if added.blink?
    sgr_param(buf, "7") if added.reverse?
    sgr_param(buf, "8") if added.hidden?
    sgr_param(buf, "9") if added.strikethrough?
  end

  # Appends one SGR parameter, inserting the ';' separator when the buffer
  # already holds a parameter (anything beyond the 2-byte "\e[" framing).
  private def sgr_param(buf : IO::Memory, param : String) : Nil
    buf.write_byte 0x3B_u8 if buf.size > 2 # ';'
    buf << param
  end

  # Appends the SGR parameter fragment selecting *color*.
  private def append_color_param(buf : IO::Memory, color : Color, *, foreground : Bool) : Nil
    if color.default?
      sgr_param(buf, foreground ? "39" : "49")
      return
    end

    case color.mode
    in .ansi8?
      sgr_param(buf, foreground ? SGR_FG_ANSI8[color.index] : SGR_BG_ANSI8[color.index])
    in .ansi256?
      sgr_param(buf, foreground ? SGR_FG_ANSI256[color.index] : SGR_BG_ANSI256[color.index])
    in .rgb?
      sgr_param(buf, foreground ? "38;2;" : "48;2;")
      buf << DECIMAL[color.r]
      buf.write_byte 0x3B_u8
      buf << DECIMAL[color.g]
      buf.write_byte 0x3B_u8
      buf << DECIMAL[color.b]
    end
  end

  # Establishes a known terminal style before consulting any style cache.
  private def ensure_style_state : Nil
    reset_attributes unless @cached_attr_known
  end

  # Resets all attributes to default.
  #
  # Also clears cached color/attribute state since reset affects all styling.
  def reset_attributes
    write(@terminfo.reset_attrs_seq)
    @cached_fg = nil
    @cached_bg = nil
    @cached_attr = Attribute::None
    @cached_attr_known = true
  end

  # Enables bold text.
  #
  # Caches attribute state to avoid redundant escape sequences.
  def enable_bold
    ensure_style_state
    return if @cached_attr.bold?
    @cached_attr |= Attribute::Bold
    write(@terminfo.bold_seq)
  end

  # Enables underline.
  #
  # Caches attribute state to avoid redundant escape sequences.
  def enable_underline
    ensure_style_state
    return if @cached_attr.underline?
    @cached_attr |= Attribute::Underline
    write(@terminfo.underline_seq)
  end

  # Enables blink.
  #
  # Caches attribute state to avoid redundant escape sequences.
  def enable_blink
    ensure_style_state
    return if @cached_attr.blink?
    @cached_attr |= Attribute::Blink
    write(@terminfo.blink_seq)
  end

  # Enables reverse video.
  #
  # Caches attribute state to avoid redundant escape sequences.
  def enable_reverse
    ensure_style_state
    return if @cached_attr.reverse?
    @cached_attr |= Attribute::Reverse
    write(@terminfo.reverse_seq)
  end

  # Enables dim/faint text.
  #
  # Caches attribute state to avoid redundant escape sequences.
  def enable_dim
    ensure_style_state
    return if @cached_attr.dim?
    @cached_attr |= Attribute::Dim
    write(@terminfo.dim_seq)
  end

  # Enables italic/cursive text.
  #
  # Caches attribute state to avoid redundant escape sequences.
  def enable_cursive
    ensure_style_state
    return if @cached_attr.cursive?
    @cached_attr |= Attribute::Cursive
    write(@terminfo.italic_seq)
  end

  # Enables hidden/invisible text.
  #
  # Caches attribute state to avoid redundant escape sequences.
  def enable_hidden
    ensure_style_state
    return if @cached_attr.hidden?
    @cached_attr |= Attribute::Hidden
    write(@terminfo.hidden_seq)
  end

  # Enables strikethrough text.
  #
  # Caches attribute state to avoid redundant escape sequences.
  def enable_strikethrough
    ensure_style_state
    return if @cached_attr.strikethrough?
    @cached_attr |= Attribute::Strikethrough
    write(@terminfo.strikethrough_seq)
  end

  # Delegates flush to backend.
  def flush
    @backend.flush
  rescue error
    invalidate_physical_render_state
    raise error
  end

  # Returns the terminal size as {width, height}.
  #
  # The value is cached to avoid an ioctl syscall on every call (write and
  # move_cursor query size on hot rendering paths). The cache is refreshed
  # by resize() and invalidated after mode switches. Use query_size to
  # force a live query.
  def size : {Int32, Int32}
    @cached_size ||= query_size
  end

  # Queries the terminal size directly from the backend.
  #
  # Always performs the live TIOCGWINSZ ioctl, bypassing the cache.
  # Intended for resize detection, which must observe external size changes.
  def query_size : {Int32, Int32}
    @backend.size
  end

  # Returns the input file descriptor for Reader.
  def infd : Int32
    @backend.infd
  end

  # Returns the output file descriptor.
  def outfd : Int32
    @backend.outfd
  end

  # Enables raw mode on the terminal.
  def enable_raw_mode
    lifecycle_log { Log.debug { "Enabling raw mode" } }
    @backend.enable_raw_mode
  end

  # Disables raw mode on the terminal.
  def disable_raw_mode
    lifecycle_log { Log.debug { "Disabling raw mode" } }
    @backend.disable_raw_mode
  end

  # Returns whether raw mode is currently enabled.
  def raw_mode? : Bool
    @backend.raw_mode?
  end

  # Executes a block with raw mode enabled, ensuring cleanup.
  def with_raw_mode(&)
    @backend.with_raw_mode { yield }
  end

  # --- Terminal Mode API ---

  # Returns the current terminal mode, or nil if not yet set.
  #
  # Delegates to underlying Backend instance.
  def current_mode : Terminal::Mode?
    @backend.current_mode
  end

  # Sets terminal to specific mode using Terminal::Mode flags.
  #
  # Updates raw_mode_enabled tracking based on whether mode is raw.
  # Does not handle screen or cursor transitions - use with_mode for that.
  #
  # Parameters:
  # - mode: Terminal::Mode flags specifying desired behavior
  #
  # Example:
  # ```
  # terminal.set_mode(Terminal::Mode.cooked)
  # terminal.set_mode(Terminal::Mode.raw)
  # ```
  # ameba:disable Naming/AccessorMethodName
  def set_mode(mode : Terminal::Mode)
    Log.debug { "Setting mode: #{mode}" }
    @backend.set_mode(mode)
  end

  # Executes a block with specific terminal mode, restoring previous mode after.
  #
  # This is the recommended way to temporarily switch modes for operations
  # like shell-out or password input. Handles:
  # - Mode switching via Backend
  # - Alternate screen exit/entry based on preserve_screen parameter
  # - Cursor visibility (shown for user-interactive modes)
  #
  # Parameters:
  # - mode: Terminal::Mode to use within the block
  # - preserve_screen: If false (default) and mode is canonical, exits alternate
  #   screen during block. If true, stays in alternate screen.
  #
  # Example:
  # ```
  # terminal.with_mode(Terminal::Mode.cooked) do
  #   system("vim file.txt")
  # end
  # # Previous mode and screen state restored
  # ```
  def with_mode(mode : Terminal::Mode, preserve_screen : Bool = false, &)
    lifecycle_log { Log.debug { "Entering with_mode: #{mode}, preserve_screen: #{preserve_screen}" } }
    user_interactive = mode.canonical? || mode.echo?

    # Track state to restore
    was_in_alternate = @alternate_screen
    was_mouse_enabled = @mouse_enabled
    was_bracketed_paste = @bracketed_paste

    # Mouse off before the block gets the tty, restored in the `ensure` from the local
    # above. The block hands fd 0 to another program — an editor, a shell, a pager — and
    # with tracking still on the emulator writes `\e[<0;40;12M` into THAT program's stdin
    # on every click. A pager shows garbage; an editor inserts the bytes into the buffer
    # being edited, which for anything editing wire-exact data is corruption.
    #
    # Must be the first thing written for the switch: neither the cursor writes below nor
    # exit_alternate_screen are guaranteed to flush on every path. Clearing the flag is
    # what makes nesting safe — an inner `with_mode` then sees it already off and its
    # restore cannot re-enable reporting while this block still owns the tty.
    if was_mouse_enabled
      apply_mouse_state false
      flush
      @mouse_enabled = false
    end

    # Mode 2004 off for the same window and by the same rule as the mouse above. Kept in
    # a method rather than inlined next to it only to hold `with_mode` under the
    # cyclomatic-complexity limit; the ordering requirement is identical.
    suspend_bracketed_paste

    backup_cursor = @cursor
    @cursor = Cursor.new visible: true
    apply_cursor_state

    # For canonical/echo modes, exit alternate screen unless preserving
    exit_alternate_screen if !preserve_screen && user_interactive && was_in_alternate

    # Switch mode via backend (handles termios and tracking)
    with_backend_mode(mode) { yield }
  ensure
    lifecycle_log { Log.debug { "Exiting with_mode, restoring state" } }
    if was_in_alternate && !@alternate_screen
      enter_alternate_screen
    end

    @cursor = backup_cursor unless backup_cursor.nil?
    apply_cursor_state
    @mouse_enabled = was_mouse_enabled unless was_mouse_enabled.nil?
    restore_bracketed_paste was_bracketed_paste
    apply_terminal_state
    # Always invalidate after non-raw modes - screen content is
    # unpredictable after puts/print/gets during the mode block
    invalidate_buffer unless mode == Terminal::Mode::None
    # Reset cached style state so next render re-emits all escape sequences.
    # External programs during the mode block may have changed terminal
    # styling, making our cached fg/bg/attr assumptions stale.
    reset_render_state
    # Drop the cached size - external programs during the mode block may
    # have resized the terminal, so the next size call re-queries live.
    @cached_size = nil
    flush
  end

  # Executes a block with cooked (shell-like) mode.
  #
  # Cooked mode enables canonical input, echo, and signal handling -
  # ideal for shell-out operations where the subprocess needs full
  # terminal control.
  #
  # By default, exits alternate screen to show the normal terminal,
  # then re-enters alternate screen after the block.
  #
  # Example:
  # ```
  # terminal.with_cooked_mode do
  #   system("vim file.txt")
  # end
  # ```
  def with_cooked_mode(preserve_screen : Bool = false, &)
    with_mode(Terminal::Mode.cooked, preserve_screen) { yield }
  end

  # Executes a block with cbreak mode.
  #
  # Cbreak mode provides character-by-character input with echo and
  # signal handling. Useful for interactive prompts where you want
  # immediate response but still show typed characters.
  #
  # By default, preserves alternate screen since cbreak is typically
  # used within a TUI context.
  #
  # Example:
  # ```
  # terminal.with_cbreak_mode do
  #   print "Press any key: "
  #   key = STDIN.read_char
  # end
  # ```
  def with_cbreak_mode(preserve_screen : Bool = true, &)
    with_mode(Terminal::Mode.cbreak, preserve_screen) { yield }
  end

  # Executes a block with password input mode.
  #
  # Password mode enables canonical (line-buffered) input with signal
  # handling but disables echo. Perfect for secure password entry.
  #
  # By default, preserves alternate screen since password prompts
  # often appear within a TUI context.
  #
  # Example:
  # ```
  # terminal.with_password_mode do
  #   print "Password: "
  #   password = gets
  # end
  # ```
  def with_password_mode(preserve_screen : Bool = true, &)
    with_mode(Terminal::Mode.password, preserve_screen) { yield }
  end

  # Closes the terminal and underlying backend.
  def close
    return unless @terminal_closed.compare_and_set(false, true)[1]

    lifecycle_log { Log.debug { "Closing terminal" } }
    error = capture_cleanup_error(nil) { disable_mouse }
    error = capture_cleanup_error(error) { disable_enhanced_keyboard }
    error = capture_cleanup_error(error) { disable_bracketed_paste }
    error = capture_cleanup_error(error) { exit_alternate_screen }
    # Backend#close restores termios and closes descriptors even if restoration
    # fails. Keep it last, but always reach it after escape-sequence failures.
    error = capture_cleanup_error(error) { @backend.close }
    raise error if error
  end

  private def capture_cleanup_error(error : Exception?, &) : Exception?
    yield
    error
  rescue ex
    error || ex
  end

  private def invalidate_physical_render_state : Nil
    @buffer.invalidate
    reset_render_state
  end

  private def lifecycle_log(&) : Nil
    yield
  rescue
    # Logging must never change lifecycle state or prevent cleanup.
  end

  # --- Cell Buffer Operations ---

  # Sets a cell at the specified position in the buffer.
  #
  # Parameters:
  # - x: Column position (0-based)
  # - y: Row position (0-based)
  # - grapheme: Character to display
  # - fg: Foreground color (default: white)
  # - bg: Background color (default: default terminal color)
  # - attr: Text attributes (default: None)
  #
  # Returns false if coordinates are out of bounds.
  # Call render() to display changes on screen.
  def set_cell(
    x : Int32,
    y : Int32,
    grapheme : String,
    fg : Color = Color.white,
    bg : Color = Color.default,
    attr : Attribute = Attribute::None,
  ) : Bool
    accepted = @buffer.set_cell(x, y, grapheme, fg, bg, attr)
    @buffer_may_be_dirty = true if accepted
    accepted
  end

  def set_cell(
    x : Int32,
    y : Int32,
    ch : Char,
    fg : Color = Color.white,
    bg : Color = Color.default,
    attr : Attribute = Attribute::None,
  ) : Bool
    accepted = @buffer.set_cell(x, y, ch, fg, bg, attr)
    @buffer_may_be_dirty = true if accepted
    accepted
  end

  # Gets a cell at the specified position from the buffer.
  #
  # Returns nil if coordinates are out of bounds.
  def get_cell(x : Int32, y : Int32) : Cell?
    @buffer.get_cell(x, y)
  end

  # Clears the cell buffer (fills with default cells).
  #
  # Call render() to display changes on screen.
  def clear_cells
    @buffer_may_be_dirty = true
    @buffer.clear
  end

  # Renders cell buffer changes to the screen.
  #
  # Only cells that have changed since the last render are redrawn (diff-based).
  # This is more efficient than full redraws for partial updates.
  #
  # When sync_updates is enabled, wraps the render in DEC mode 2026 sequences
  # (BSU/ESU) to prevent screen tearing during rapid updates.
  def render : Nil
    if !@buffer_may_be_dirty && @established_cursor == @cursor
      flush
      return
    end

    render_transaction do
      @buffer.render_to(self, auto_flush: false)
    end
    @established_cursor = @cursor
    @buffer_may_be_dirty = false
    nil
  rescue error
    invalidate_physical_render_state
    raise error
  end

  # Forces a full redraw of all cells.
  #
  # Useful after terminal resize or screen corruption.
  #
  # When sync_updates is enabled, wraps the sync in DEC mode 2026 sequences
  # (BSU/ESU) to prevent screen tearing during the full redraw.
  def sync : Nil
    render_transaction do
      @buffer.sync_to(self, auto_flush: false)
    end
    @established_cursor = @cursor
    @buffer_may_be_dirty = false
    nil
  rescue error
    invalidate_physical_render_state
    raise error
  end

  # Keeps Buffer and Terminal caches provisional until every operation around
  # a frame, including synchronized-update framing and its flush, succeeds.
  # Buffer handles failures from its direct renderer calls; this outer guard
  # also covers BSU/ESU and restores cache truth for Terminal's renderer state.
  private def render_transaction(&)
    primary_error : Exception? = nil

    begin
      begin_sync_update
      with_ephemeral_cursor { yield }
    rescue error
      primary_error = error
    ensure
      # BSU writes can fail after partial output, so attempt ESU and the final
      # flush even when beginning or rendering fails. Preserve the first error.
      primary_error = capture_cleanup_error(primary_error) { end_sync_update }
      primary_error = capture_cleanup_error(primary_error) { flush }
    end

    raise primary_error if primary_error
  end

  # Emits BSU (Begin Synchronized Update) sequence if sync_updates is enabled.
  private def begin_sync_update
    write(BSU) if @sync_updates
  end

  # Emits ESU (End Synchronized Update) sequence if sync_updates is enabled.
  # The transaction flushes after cursor restoration and this closing sequence.
  private def end_sync_update
    write(ESU) if @sync_updates
  end

  # Invalidates the buffer, forcing a full re-render on next render().
  #
  # Call this after the terminal screen has been cleared externally.
  # Unlike sync(), this doesn't render immediately - it marks the buffer
  # so the next render() call will redraw everything.
  def invalidate_buffer
    @established_cursor = nil
    @buffer.invalidate
  end

  # Resizes the buffer to new dimensions.
  #
  # Preserves existing content where possible. Also refreshes the cached
  # size so subsequent size calls reflect the new dimensions.
  def resize(width : Int32, height : Int32)
    @buffer_may_be_dirty = true
    @cached_size = {width, height}
    @buffer.resize(width, height)
    move_cursor
  end

  # --- Synchronized Updates (DEC Private Mode 2026) ---

  # Synchronized update escape sequences.
  # Prevents screen tearing by buffering output between BSU and ESU.
  # Supported by: Windows Terminal, Kitty, iTerm2, Wezterm, Alacritty 0.13+,
  # foot, mintty, Ghostty. Unsupported terminals simply ignore these sequences.
  BSU = "\e[?2026h" # Begin Synchronized Update
  ESU = "\e[?2026l" # End Synchronized Update

  # Returns whether synchronized updates are enabled.
  #
  # When enabled, render operations are wrapped in BSU/ESU sequences
  # to prevent screen tearing. Enabled by default.
  getter? sync_updates : Bool

  # Sets whether synchronized updates are enabled.
  #
  # Can be toggled at runtime. Set to false for debugging or
  # compatibility with terminals that misbehave with sync sequences.
  setter sync_updates : Bool

  # --- Mouse Support ---

  # Mouse protocol escape sequences.
  # Using CSI ? sequences for xterm-compatible mouse tracking.
  MOUSE_ENABLE_NORMAL  = "\e[?1000h" # Normal mouse tracking (mode 1000)
  MOUSE_ENABLE_SGR     = "\e[?1006h" # SGR extended mouse protocol (mode 1006)
  MOUSE_DISABLE_NORMAL = "\e[?1000l"
  MOUSE_DISABLE_SGR    = "\e[?1006l"

  # Enhanced keyboard protocol escape sequences.
  # These protocols disambiguate keys that normally send the same bytes
  # (e.g., Tab vs Ctrl+I, Enter vs Ctrl+M).
  #
  # Kitty keyboard protocol (most comprehensive):
  #   https://sw.kovidgoyal.net/kitty/keyboard-protocol/
  #   Flags: 1=disambiguate, 2=report_event_types, 4=report_alternate_keys
  #         8=report_all_keys, 16=report_text
  KITTY_KEYBOARD_ENABLE  = "\e[>17u" # disambiguate + report_text (safer for Hangul IME compose than 31u)
  KITTY_KEYBOARD_DISABLE = "\e[<u"   # Pop keyboard mode

  # modifyOtherKeys (xterm, widely supported):
  #   Mode 2 reports modified keys as CSI 27 ; modifier ; keycode ~
  MODIFY_OTHER_KEYS_ENABLE  = "\e[>4;2m" # Enable mode 2
  MODIFY_OTHER_KEYS_DISABLE = "\e[>4;0m" # Disable

  # Bracketed paste escape sequences (DEC private mode 2004).
  #
  # While enabled the terminal wraps pasted text in \e[200~ ... \e[201~ and
  # hands the bytes between them over verbatim, without the CR/LF translation
  # it applies to typed input. Terminals that don't implement it ignore the
  # sequences and keep sending pastes as plain input.
  BRACKETED_PASTE_ENABLE  = "\e[?2004h"
  BRACKETED_PASTE_DISABLE = "\e[?2004l"

  # Enables mouse input tracking.
  #
  # Enables SGR extended mouse protocol (mode 1006) for better coordinate
  # support and unambiguous button detection. Falls back to normal mode
  # (1000) on older terminals that don't support SGR.
  #
  # Example:
  # ```
  # terminal.enable_mouse
  # # Now mouse events will be reported via poll_event
  # terminal.disable_mouse # When done
  # ```
  def enable_mouse
    return if @mouse_enabled
    Log.debug { "Enabling mouse tracking" }
    apply_mouse_state true
    flush
    @mouse_enabled = true
  end

  # Disables mouse input tracking.
  #
  # Disables both SGR and normal mouse protocols.
  def disable_mouse
    return unless @mouse_enabled
    lifecycle_log { Log.debug { "Disabling mouse tracking" } }
    @mouse_enabled = false
    apply_mouse_state false
    flush
  end

  # Returns whether mouse tracking is currently enabled.
  def mouse_enabled? : Bool
    @mouse_enabled
  end

  # --- Enhanced Keyboard Support ---

  # Enables enhanced keyboard protocol for disambiguated key reporting.
  #
  # This enables the Kitty keyboard protocol (if supported) and falls back
  # to modifyOtherKeys. Enhanced mode allows distinguishing between keys
  # that normally send the same bytes:
  # - Tab vs Ctrl+I
  # - Enter vs Ctrl+M
  # - Backspace vs Ctrl+H
  #
  # Not all terminals support these protocols. Unsupported terminals will
  # simply ignore the escape sequences and continue with legacy behavior.
  #
  # Example:
  # ```
  # terminal.enable_enhanced_keyboard
  # # Now Ctrl+I and Tab are distinguishable
  # terminal.disable_enhanced_keyboard # When done
  # ```
  def enable_enhanced_keyboard
    return if @enhanced_keyboard
    Log.debug { "Enabling enhanced keyboard protocol" }
    apply_enhanced_keyboard_state true
    flush
    @enhanced_keyboard = true
  end

  # Disables enhanced keyboard protocol.
  #
  # Returns to legacy keyboard mode where Tab/Ctrl+I, Enter/Ctrl+M, etc.
  # are indistinguishable.
  def disable_enhanced_keyboard
    return unless @enhanced_keyboard
    lifecycle_log { Log.debug { "Disabling enhanced keyboard protocol" } }
    @enhanced_keyboard = false
    apply_enhanced_keyboard_state false
    flush
  end

  # Returns whether enhanced keyboard protocol is enabled.
  def enhanced_keyboard? : Bool
    @enhanced_keyboard
  end

  # --- Bracketed Paste Support ---

  # Enables bracketed paste mode.
  #
  # The terminal then wraps pasted text in \e[200~ ... \e[201~, which the input
  # parser surfaces as `Input::Key::PasteStart` / `Input::Key::PasteEnd`, and
  # stops translating line endings inside the paste.
  #
  # Without it a paste is indistinguishable from typing: a pasted CRLF arrives
  # as the same bytes Enter produces, and some terminals map the LF to a second
  # CR so one pasted line break looks exactly like two deliberate Enters. No
  # amount of content inspection can separate those, which is why the boundary
  # markers are the only correct fix.
  #
  # The bytes between the markers are still reported exactly as they arrive (a
  # pasted CR is `Key::Enter` with `char == '\r'`): the markers say *where* the
  # paste is, they do not normalize what is inside it.
  #
  # Example:
  # ```
  # terminal.enable_bracketed_paste
  # # Pastes are now delimited by Key::PasteStart / Key::PasteEnd
  # terminal.disable_bracketed_paste # When done
  # ```
  def enable_bracketed_paste
    return if @bracketed_paste
    Log.debug { "Enabling bracketed paste" }
    apply_bracketed_paste_state true
    flush
    @bracketed_paste = true
  end

  # Disables bracketed paste mode.
  #
  # Pasted text goes back to arriving as plain input with no boundary markers.
  def disable_bracketed_paste
    return unless @bracketed_paste
    lifecycle_log { Log.debug { "Disabling bracketed paste" } }
    @bracketed_paste = false
    apply_bracketed_paste_state false
    flush
  end

  # Returns whether bracketed paste mode is currently enabled.
  def bracketed_paste? : Bool
    @bracketed_paste
  end

  private def apply_terminal_state
    apply_mouse_state @mouse_enabled
    apply_enhanced_keyboard_state @enhanced_keyboard
    # Guarded, unlike the two above: a caller that never asked for bracketed
    # paste must not see 2004h/2004l on the wire at all, and re-asserting "off"
    # would clobber the mode for an embedding application that set it itself.
    apply_bracketed_paste_state true if @bracketed_paste
  end

  # Puts the caller's mode-2004 state back after a `with_mode` block, reconciling the
  # wire with the flag first.
  #
  # A block that turned the mode ON while it was off outside leaves 2004h at the terminal,
  # and *was_enabled* is about to record it as off. `apply_terminal_state` would write
  # nothing — its re-apply is guarded so a caller who never asked for 2004 never sees it
  # on the wire — and `disable_bracketed_paste` and `close` are guarded on the same flag,
  # so nothing could ever clear it and the mode would outlive the process. The mouse path
  # self-heals in this scenario only because its re-apply is unconditional, which is the
  # trade the guard here deliberately does not make.
  private def restore_bracketed_paste(was_enabled : Bool?) : Nil
    apply_bracketed_paste_state(false) if @bracketed_paste && !was_enabled
    @bracketed_paste = was_enabled unless was_enabled.nil?
  end

  # Turns mode 2004 off for the duration of a `with_mode` block, restored by
  # `apply_terminal_state` from the caller's saved flag.
  #
  # `with_mode` hands the tty to something else — an editor, a shell, a cooked `gets` —
  # and that something never asked for bracketing: it would receive `\e[200~` literals it
  # does not understand, and a mode left on after the process exits is a defect of its
  # own. Clearing `@bracketed_paste` is what makes nesting safe, exactly as clearing
  # `@mouse_enabled` does: an inner scope then sees it already off, and its restore cannot
  # put 2004h back while the outer block still owns the tty.
  private def suspend_bracketed_paste
    return unless @bracketed_paste
    apply_bracketed_paste_state false
    flush
    @bracketed_paste = false
  end

  # The single step of `with_mode` that needs a live tty, split out so a test double can
  # replace just this and inherit everything around it. Overriding `with_mode` wholesale
  # means a spec drives its own copy of the ordering above, and a regression in the real
  # one passes unnoticed.
  private def with_backend_mode(mode : Terminal::Mode, &)
    @backend.with_mode(mode) { yield }
  end

  private def apply_mouse_state(enabled : Bool)
    # Enable SGR mode first (preferred), then normal mode as fallback.
    if enabled
      write(MOUSE_ENABLE_SGR)
      write(MOUSE_ENABLE_NORMAL)
    else
      write(MOUSE_DISABLE_SGR)
      write(MOUSE_DISABLE_NORMAL)
    end
  end

  private def apply_enhanced_keyboard_state(enabled : Bool)
    # Try Kitty first (most comprehensive), then modifyOtherKeys as fallback.
    if enabled
      write(KITTY_KEYBOARD_ENABLE)
      write(MODIFY_OTHER_KEYS_ENABLE)
    else
      write(KITTY_KEYBOARD_DISABLE)
      write(MODIFY_OTHER_KEYS_DISABLE)
    end
  end

  private def apply_bracketed_paste_state(enabled : Bool)
    write(enabled ? BRACKETED_PASTE_ENABLE : BRACKETED_PASTE_DISABLE)
  end

  def title=(title : String)
    return title if title == @title
    write(@terminfo.to_status_line_seq + title + @terminfo.from_status_line_seq)
    @title = title
  end
end

require "./terminal/*"
