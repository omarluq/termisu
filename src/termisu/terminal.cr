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
  @sync_updates : Bool = true
  getter cursor : Cursor = Cursor.new
  getter title : String = ""

  # Cached render state for direct API optimization.
  # Prevents redundant escape sequences when the same style is set repeatedly.
  @cached_fg : Color?
  @cached_bg : Color?
  @cached_attr : Attribute = Attribute::None

  # Creates a new terminal.
  #
  # Parameters:
  # - `backend` - Terminal::Backend instance for I/O operations (default: Terminal::Backend.new)
  # - `terminfo` - Terminfo instance for capability strings (default: Terminfo.new)
  # - `sync_updates` - Enable DEC mode 2026 synchronized updates (default: true)
  def initialize(
    @backend : Terminal::Backend = Terminal::Backend.new,
    @terminfo : Terminfo = Terminfo.new,
    *,
    @sync_updates : Bool = true,
  )
    width, height = size
    @buffer = Buffer.new(width, height)
    Log.debug { "Terminal initialized: #{width}x#{height}, sync_updates: #{@sync_updates}" }
  end

  # Enters alternate screen mode.
  #
  # Switches to alternate screen buffer, clears the screen,
  # enters keypad mode, and hides cursor. Also resets cached
  # render state since we're entering a fresh screen.
  def enter_alternate_screen
    return if @alternate_screen
    Log.debug { "Entering alternate screen" }
    write(@terminfo.enter_ca_seq)
    write(@terminfo.clear_screen_seq)
    write(@terminfo.enter_keypad_seq)
    reset_render_state
    apply_cursor_state
    flush
    @alternate_screen = true
  end

  # Exits alternate screen mode.
  #
  # Shows cursor, exits keypad mode, and returns to main screen buffer.
  # Also resets cached render state since we're returning to the
  # main screen which may have different state.
  def exit_alternate_screen
    return unless @alternate_screen
    Log.debug { "Exiting alternate screen" }
    @cursor = Cursor.new visible: true
    apply_cursor_state
    write(@terminfo.exit_keypad_seq)
    write(@terminfo.exit_ca_seq)
    reset_render_state
    flush
    @alternate_screen = false
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
  end

  # Sets the foreground color with full ANSI-8, ANSI-256, and RGB support.
  #
  # Caches the color to avoid redundant escape sequences when called
  # repeatedly with the same color.
  def foreground=(color : Color)
    return if @cached_fg == color
    @cached_fg = color

    if color.default?
      write("\e[39m") # Default foreground
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

  # Sets the background color with full ANSI-8, ANSI-256, and RGB support.
  #
  # Caches the color to avoid redundant escape sequences when called
  # repeatedly with the same color.
  def background=(color : Color)
    return if @cached_bg == color
    @cached_bg = color

    if color.default?
      write("\e[49m") # Default background
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

  # Resets all attributes to default.
  #
  # Also clears cached color/attribute state since reset affects all styling.
  def reset_attributes
    write(@terminfo.reset_attrs_seq)
    @cached_fg = nil
    @cached_bg = nil
    @cached_attr = Attribute::None
  end

  # Enables bold text.
  #
  # Caches attribute state to avoid redundant escape sequences.
  def enable_bold
    return if @cached_attr.bold?
    @cached_attr |= Attribute::Bold
    write(@terminfo.bold_seq)
  end

  # Enables underline.
  #
  # Caches attribute state to avoid redundant escape sequences.
  def enable_underline
    return if @cached_attr.underline?
    @cached_attr |= Attribute::Underline
    write(@terminfo.underline_seq)
  end

  # Enables blink.
  #
  # Caches attribute state to avoid redundant escape sequences.
  def enable_blink
    return if @cached_attr.blink?
    @cached_attr |= Attribute::Blink
    write(@terminfo.blink_seq)
  end

  # Enables reverse video.
  #
  # Caches attribute state to avoid redundant escape sequences.
  def enable_reverse
    return if @cached_attr.reverse?
    @cached_attr |= Attribute::Reverse
    write(@terminfo.reverse_seq)
  end

  # Enables dim/faint text.
  #
  # Caches attribute state to avoid redundant escape sequences.
  def enable_dim
    return if @cached_attr.dim?
    @cached_attr |= Attribute::Dim
    write(@terminfo.dim_seq)
  end

  # Enables italic/cursive text.
  #
  # Caches attribute state to avoid redundant escape sequences.
  def enable_cursive
    return if @cached_attr.cursive?
    @cached_attr |= Attribute::Cursive
    write(@terminfo.italic_seq)
  end

  # Enables hidden/invisible text.
  #
  # Caches attribute state to avoid redundant escape sequences.
  def enable_hidden
    return if @cached_attr.hidden?
    @cached_attr |= Attribute::Hidden
    write(@terminfo.hidden_seq)
  end

  # Enables strikethrough text.
  #
  # Caches attribute state to avoid redundant escape sequences.
  def enable_strikethrough
    return if @cached_attr.strikethrough?
    @cached_attr |= Attribute::Strikethrough
    write(@terminfo.strikethrough_seq)
  end

  # Delegates flush to backend.
  def flush
    @backend.flush
  end

  # Delegates size to backend.
  def size : {Int32, Int32}
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
    Log.debug { "Enabling raw mode" }
    @backend.enable_raw_mode
  end

  # Disables raw mode on the terminal.
  def disable_raw_mode
    Log.debug { "Disabling raw mode" }
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
    Log.debug { "Entering with_mode: #{mode}, preserve_screen: #{preserve_screen}" }
    user_interactive = mode.canonical? || mode.echo?

    # Track state to restore
    was_in_alternate = @alternate_screen

    backup_cursor = @cursor
    @cursor = Cursor.new visible: true
    apply_cursor_state

    # For canonical/echo modes, exit alternate screen unless preserving
    exit_alternate_screen if !preserve_screen && user_interactive && was_in_alternate

    # Switch mode via backend (handles termios and tracking)
    @backend.with_mode(mode) { yield }
  ensure
    Log.debug { "Exiting with_mode, restoring state" }
    if was_in_alternate && !@alternate_screen
      enter_alternate_screen
    end

    @cursor = backup_cursor unless backup_cursor.nil?
    apply_cursor_state
    apply_terminal_state
    # Always invalidate after non-raw modes - screen content is
    # unpredictable after puts/print/gets during the mode block
    invalidate_buffer unless mode.none?
    # Reset cached style state so next render re-emits all escape sequences.
    # External programs during the mode block may have changed terminal
    # styling, making our cached fg/bg/attr assumptions stale.
    reset_render_state
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
    Log.debug { "Closing terminal" }
    disable_mouse
    disable_enhanced_keyboard
    exit_alternate_screen
    disable_raw_mode
    @backend.close
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
  delegate set_cell, to: @buffer

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
    @buffer.clear
  end

  # Renders cell buffer changes to the screen.
  #
  # Only cells that have changed since the last render are redrawn (diff-based).
  # This is more efficient than full redraws for partial updates.
  #
  # When sync_updates is enabled, wraps the render in DEC mode 2026 sequences
  # (BSU/ESU) to prevent screen tearing during rapid updates.
  def render
    begin_sync_update
    begin
      with_ephemeral_cursor do
        @buffer.render_to(self, auto_flush: !@sync_updates)
      end
    ensure
      end_sync_update
    end
  end

  # Forces a full redraw of all cells.
  #
  # Useful after terminal resize or screen corruption.
  #
  # When sync_updates is enabled, wraps the sync in DEC mode 2026 sequences
  # (BSU/ESU) to prevent screen tearing during the full redraw.
  def sync
    begin_sync_update
    begin
      with_ephemeral_cursor do
        @buffer.sync_to(self, auto_flush: !@sync_updates)
      end
    ensure
      end_sync_update
    end
  end

  # Emits BSU (Begin Synchronized Update) sequence if sync_updates is enabled.
  private def begin_sync_update
    write(BSU) if @sync_updates
  end

  # Emits ESU (End Synchronized Update) sequence and flushes if sync_updates is enabled.
  private def end_sync_update
    return unless @sync_updates
    write(ESU)
    flush
  end

  # Invalidates the buffer, forcing a full re-render on next render().
  #
  # Call this after the terminal screen has been cleared externally.
  # Unlike sync(), this doesn't render immediately - it marks the buffer
  # so the next render() call will redraw everything.
  def invalidate_buffer
    @buffer.invalidate
  end

  # Resizes the buffer to new dimensions.
  #
  # Preserves existing content where possible.
  def resize(width : Int32, height : Int32)
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
  KITTY_KEYBOARD_ENABLE  = "\e[>1u" # Enable with disambiguate flag
  KITTY_KEYBOARD_DISABLE = "\e[<u"  # Pop keyboard mode

  # modifyOtherKeys (xterm, widely supported):
  #   Mode 2 reports modified keys as CSI 27 ; modifier ; keycode ~
  MODIFY_OTHER_KEYS_ENABLE  = "\e[>4;2m" # Enable mode 2
  MODIFY_OTHER_KEYS_DISABLE = "\e[>4;0m" # Disable

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
    # Enable SGR mode first (preferred), then normal mode as fallback
    write(MOUSE_ENABLE_SGR)
    write(MOUSE_ENABLE_NORMAL)
    flush
    @mouse_enabled = true
  end

  # Disables mouse input tracking.
  #
  # Disables both SGR and normal mouse protocols.
  def disable_mouse
    return unless @mouse_enabled
    Log.debug { "Disabling mouse tracking" }
    write(MOUSE_DISABLE_SGR)
    write(MOUSE_DISABLE_NORMAL)
    flush
    @mouse_enabled = false
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
    # Try Kitty first (most comprehensive), then modifyOtherKeys as fallback
    write(KITTY_KEYBOARD_ENABLE)
    write(MODIFY_OTHER_KEYS_ENABLE)
    flush
    @enhanced_keyboard = true
  end

  # Disables enhanced keyboard protocol.
  #
  # Returns to legacy keyboard mode where Tab/Ctrl+I, Enter/Ctrl+M, etc.
  # are indistinguishable.
  def disable_enhanced_keyboard
    return unless @enhanced_keyboard
    Log.debug { "Disabling enhanced keyboard protocol" }
    write(KITTY_KEYBOARD_DISABLE)
    write(MODIFY_OTHER_KEYS_DISABLE)
    flush
    @enhanced_keyboard = false
  end

  # Returns whether enhanced keyboard protocol is enabled.
  def enhanced_keyboard? : Bool
    @enhanced_keyboard
  end

  private def apply_terminal_state
    if @mouse_enabled
      @mouse_enabled = false
      enable_mouse
    else
      @mouse_enabled = true
      disable_mouse
    end

    if @enhanced_keyboard
      @enhanced_keyboard = false
      enable_enhanced_keyboard
    else
      @enhanced_keyboard = true
      disable_enhanced_keyboard
    end
  end

  def title=(title : String)
    return title if title == @title
    write(@terminfo.to_status_line_seq + title + @terminfo.from_status_line_seq)
    @title = title
  end
end

require "./terminal/*"
