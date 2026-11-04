# Terminal attribute manipulation for mode control.
#
# Provides low-level terminal control via POSIX termios API.
# Supports multiple terminal modes (raw, cooked, cbreak, password)
# and restoring original settings.
#
# Example:
# ```
# termios = Termisu::Termios.new(STDIN.fd)
# termios.enable_raw_mode
# # Terminal is now in raw mode - no echo, no line buffering
# termios.restore # Restore original settings
#
# # Or use specific modes:
# termios.set_mode(Terminal::Mode.cooked)
# termios.set_mode(Terminal::Mode.password)
# ```

# Define missing termios constants for platforms where they're not in LibC
lib LibC
  {% unless LibC.has_constant?(:VMIN) %}
    VMIN = 16
  {% end %}
  {% unless LibC.has_constant?(:VTIME) %}
    VTIME = 17
  {% end %}
end

# Manages terminal attributes for mode control.
#
# Supports multiple modes via Terminal::Mode flags:
# - Raw: No processing (current Termisu default for TUI)
# - Cooked: Full line editing, echo, signals (shell-out)
# - Cbreak: Char-by-char with echo and signals
# - Password: Line editing without echo
# - SemiRaw: Raw with signal handling
class Termisu::Termios
  @fd : IO::FileDescriptor::Handle
  {% if flag?(:win32) %}
    @output_fd : IO::FileDescriptor::Handle?
    @original_input_mode : UInt32?
    @original_output_mode : UInt32?
  {% else %}
    @original : LibC::Termios?
  {% end %}
  @current_mode : Terminal::Mode?

  # Returns the current terminal mode, or nil if not yet set.
  getter current_mode : Terminal::Mode?

  # Creates a new Termios instance for the given file descriptor.
  #
  # Parameters:
  # - fd: File descriptor (typically STDIN.fd for terminal input)
  {% if flag?(:win32) %}
    def initialize(@fd : IO::FileDescriptor::Handle, @output_fd : IO::FileDescriptor::Handle? = nil)
    end
  {% else %}
    def initialize(@fd : IO::FileDescriptor::Handle)
    end
  {% end %}

  # Enables raw mode on the terminal.
  #
  # Saves current attributes and modifies terminal to disable:
  # - Input processing and special character handling
  # - Echo of typed characters
  # - Canonical (line-buffered) mode
  # - Signal generation from Ctrl+C, Ctrl+Z, etc.
  #
  # This is a convenience method equivalent to `set_mode(Terminal::Mode.raw)`.
  def enable_raw_mode
    set_mode(Terminal::Mode.raw)
  end

  # Sets terminal to specific mode using Terminal::Mode flags.
  #
  # Saves original terminal state on first call, then applies the
  # requested mode flags to control terminal behavior.
  #
  # Parameters:
  # - mode: Terminal::Mode flags specifying desired behavior
  #
  # Example:
  # ```
  # termios.set_mode(Terminal::Mode.cooked)   # Shell-out mode
  # termios.set_mode(Terminal::Mode.password) # No echo, line editing
  # termios.set_mode(Terminal::Mode.raw)      # Full TUI control
  # ```
  # ameba:disable Naming/AccessorMethodName
  def set_mode(mode : Terminal::Mode)
    {% if flag?(:win32) %}
      set_console_mode(mode)
    {% else %}
      # Save original state on first mode change
      @original ||= get_attrs

      orig = @original
      return unless orig

      tios = orig.dup

      # Clear controlled local flags (we'll set what's needed)
      controlled_lflag = LibC::ICANON | LibC::ECHO | LibC::ISIG | LibC::IEXTEN
      tios.c_lflag &= ~controlled_lflag

      # Apply requested local mode flags
      tios.c_lflag |= LibC::ICANON if mode.canonical?
      tios.c_lflag |= LibC::ECHO if mode.echo?
      tios.c_lflag |= LibC::ISIG if mode.signals?
      tios.c_lflag |= LibC::IEXTEN if mode.extended?

      # Input flags handling
      tios = apply_input_flags(tios, orig, mode)

      # Output flags handling
      tios = apply_output_flags(tios, orig, mode)

      # Control flags - 8-bit chars, no parity
      tios.c_cflag &= ~(LibC::CSIZE | LibC::PARENB)
      tios.c_cflag |= LibC::CS8

      # Control chars for non-canonical modes
      unless mode.canonical?
        tios.c_cc[LibC::VMIN] = 1_u8  # Read returns after 1 char
        tios.c_cc[LibC::VTIME] = 0_u8 # No timeout
      end

      set_attrs(tios)
    {% end %}
    @current_mode = mode
  end

  # Restores original terminal attributes saved during first mode change.
  #
  # Safe to call even if no mode was ever set (no-op).
  # Resets current_mode tracking to nil.
  def restore
    {% if flag?(:win32) %}
      restore_console_modes(@original_input_mode, @original_output_mode)
    {% else %}
      @original.try(&->set_attrs(LibC::Termios))
    {% end %}
    @current_mode = nil
  end

  {% if flag?(:win32) %}
    private def console_mode(fd : IO::FileDescriptor::Handle) : UInt32
      if LibC.GetConsoleMode(LibC::HANDLE.new(fd), out mode) == 0
        raise IO::Error.from_winerror("GetConsoleMode")
      end
      mode
    end

    private def apply_console_mode(fd : IO::FileDescriptor::Handle, mode : UInt32) : Nil
      if LibC.SetConsoleMode(LibC::HANDLE.new(fd), mode) == 0
        raise IO::Error.from_winerror("SetConsoleMode")
      end
    end

    private def restore_console_modes(input : UInt32?, output : UInt32?) : Nil
      error : Exception? = nil
      begin
        apply_console_mode(@fd, input) if input
      rescue ex
        error = ex
      end
      begin
        if (fd = @output_fd) && output
          apply_console_mode(fd, output)
        end
      rescue ex
        error ||= ex
      end
      raise error if error
    end

    private def set_console_mode(mode : Terminal::Mode) : Nil
      if mode.echo? && !mode.canonical?
        raise NotImplementedError.new("Windows console echo requires canonical input")
      end
      input = console_mode(@fd)
      output = @output_fd.try { |fd| console_mode(fd) }
      original = @original_input_mode ||= input
      @original_output_mode ||= output
      controlled = (LibC::ENABLE_LINE_INPUT | LibC::ENABLE_ECHO_INPUT |
                    LibC::ENABLE_PROCESSED_INPUT | LibC::ENABLE_VIRTUAL_TERMINAL_INPUT).to_u32
      bits = original & ~controlled
      if mode.canonical?
        bits |= LibC::ENABLE_LINE_INPUT
        bits |= LibC::ENABLE_ECHO_INPUT if mode.echo?
      else
        bits |= LibC::ENABLE_VIRTUAL_TERMINAL_INPUT | System::Console::C::ENABLE_MOUSE_INPUT
        bits = (bits | System::Console::C::ENABLE_EXTENDED_FLAGS) & ~System::Console::C::ENABLE_QUICK_EDIT_MODE
      end
      bits |= LibC::ENABLE_PROCESSED_INPUT if mode.signals?
      begin
        apply_console_mode(@fd, bits)
        if (fd = @output_fd) && (original_output = @original_output_mode)
          # Defer right-edge wrapping until text arrives, as the shared renderer assumes.
          output_bits = mode.canonical? ? original_output : original_output | 0x000D_u32
          apply_console_mode(fd, output_bits)
        end
      rescue error
        restore_console_modes(input, output) rescue nil
        raise error
      end
    end
  {% else %}
    private def get_attrs : LibC::Termios
      tios = uninitialized LibC::Termios
      if LibC.tcgetattr(@fd, pointerof(tios)) != 0
        raise IO::Error.from_errno("tcgetattr failed")
      end
      tios
    end

    private def set_attrs(tios : LibC::Termios)
      # Create a copy to pass to tcsetattr
      tios_copy = tios
      if LibC.tcsetattr(@fd, LibC::TCSAFLUSH, pointerof(tios_copy)) != 0
        raise IO::Error.from_errno("tcsetattr failed")
      end
    end

    # Applies input flags (c_iflag) based on mode, returning the updated attrs.
    # Handles IXON (flow control) and ICRNL (CR→NL translation).
    #
    # RETURNS the struct rather than mutating the argument: `LibC::Termios` is a
    # struct, so the parameter is a COPY and every assignment here was discarded on
    # return. Only c_lflag/c_cflag/c_cc, mutated inline in `set_mode`, ever reached
    # the terminal — which is why `current_mode` and ICANON/ECHO looked right while
    # raw mode kept ICRNL, IXON and OPOST set, the opposite of the table in
    # `Terminal::Mode`. With ICRNL on the line discipline rewrites every CR to NL
    # before any read sees it, so a pasted CRLF arrives as two newlines; with IXON
    # on, Ctrl+S freezes a full-screen application instead of arriving as a key.
    private def apply_input_flags(tios : LibC::Termios, orig : LibC::Termios, mode : Terminal::Mode) : LibC::Termios
      if mode.canonical?
        # Start with original input flags for canonical mode
        tios.c_iflag = orig.c_iflag

        # But still respect explicit flag settings
        if !mode.flow_control?
          tios.c_iflag &= ~LibC::IXON
        end
        if !mode.cr_to_nl?
          tios.c_iflag &= ~LibC::ICRNL
        end
      else
        # Clear input processing for raw/cbreak modes
        tios.c_iflag &= ~(LibC::IGNBRK | LibC::BRKINT | LibC::PARMRK |
                          LibC::ISTRIP | LibC::INLCR | LibC::IGNCR |
                          LibC::ICRNL | LibC::IXON)

        # Apply explicit flag requests
        tios.c_iflag |= LibC::IXON if mode.flow_control?
        tios.c_iflag |= LibC::ICRNL if mode.cr_to_nl?
      end
      tios
    end

    # Applies output flags (c_oflag) based on mode, returning the updated attrs.
    # Handles OPOST (output processing) for NL→CRNL translation etc.
    # Returns rather than mutates — see `apply_input_flags`.
    private def apply_output_flags(tios : LibC::Termios, orig : LibC::Termios, mode : Terminal::Mode) : LibC::Termios
      if mode.canonical?
        # Start with original output flags for canonical mode
        tios.c_oflag = orig.c_oflag

        # But still respect explicit flag settings
        if !mode.output_processing?
          tios.c_oflag &= ~LibC::OPOST
        end
      else
        # Clear output processing for raw modes by default
        tios.c_oflag &= ~LibC::OPOST

        # Apply explicit flag request
        tios.c_oflag |= LibC::OPOST if mode.output_processing?
      end
      tios
    end
  {% end %}
end
