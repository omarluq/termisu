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
  @fd : Int32
  @original : LibC::Termios?
  @current_mode : Terminal::Mode?

  # Returns the current terminal mode, or nil if not yet set.
  getter current_mode : Terminal::Mode?

  # Creates a new Termios instance for the given file descriptor.
  #
  # Parameters:
  # - fd: File descriptor (typically STDIN.fd for terminal input)
  def initialize(@fd : Int32)
  end

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
    # Save original state on first mode change
    @original ||= get_attrs

    orig = @original
    return unless orig

    tios = orig.dup

    # Clear controlled local flags (we'll set what's needed)
    controlled_lflag = LibC::ICANON | LibC::ECHO | LibC::ISIG | LibC::IEXTEN
    tios.c_lflag &= ~controlled_lflag

    # Apply requested mode flags
    tios.c_lflag |= LibC::ICANON if mode.canonical?
    tios.c_lflag |= LibC::ECHO if mode.echo?
    tios.c_lflag |= LibC::ISIG if mode.signals?
    tios.c_lflag |= LibC::IEXTEN if mode.extended?

    # Input flags handling
    if mode.canonical?
      # Restore original input flags for canonical mode (shell-like behavior)
      # This preserves CR→NL translation, flow control, etc.
      tios.c_iflag = orig.c_iflag
    else
      # Clear input processing for raw/cbreak modes (TUI compatibility)
      tios.c_iflag &= ~(LibC::IGNBRK | LibC::BRKINT | LibC::PARMRK |
                        LibC::ISTRIP | LibC::INLCR | LibC::IGNCR |
                        LibC::ICRNL | LibC::IXON)
    end

    # Control flags - 8-bit chars, no parity
    tios.c_cflag &= ~(LibC::CSIZE | LibC::PARENB)
    tios.c_cflag |= LibC::CS8

    # Control chars for non-canonical modes
    unless mode.canonical?
      tios.c_cc[LibC::VMIN] = 1_u8  # Read returns after 1 char
      tios.c_cc[LibC::VTIME] = 0_u8 # No timeout
    end

    set_attrs(tios)
    @current_mode = mode
  end

  # Restores original terminal attributes saved during first mode change.
  #
  # Safe to call even if no mode was ever set (no-op).
  # Resets current_mode tracking to nil.
  def restore
    @original.try(&->set_attrs(LibC::Termios))
    @current_mode = nil
  end

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
end
