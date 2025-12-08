# Terminal attribute manipulation for raw mode control.
#
# Provides low-level terminal control via POSIX termios API.
# Supports enabling raw mode (disabling input processing, echo, signals)
# and restoring original settings.
#
# Example:
# ```
# termios = Termisu::Termios.new(STDIN.fd)
# termios.enable_raw_mode
# # Terminal is now in raw mode - no echo, no line buffering
# termios.restore # Restore original settings
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

# Manages terminal attributes for raw mode operation.
#
# Raw mode disables:
# - Input processing (IGNBRK, BRKINT, PARMRK, ISTRIP, INLCR, IGNCR, ICRNL, IXON)
# - Echo and canonical mode (ECHO, ECHONL, ICANON, ISIG, IEXTEN)
# - Parity checking, sets 8-bit characters (CS8)
class Termisu::Termios
  @fd : Int32
  @original : LibC::Termios?

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
  def enable_raw_mode
    @original = get_attrs
    tios = @original.try(&.dup)
    return unless tios

    # Input flags - turn off input processing
    tios.c_iflag &= ~(LibC::IGNBRK | LibC::BRKINT | LibC::PARMRK |
                      LibC::ISTRIP | LibC::INLCR | LibC::IGNCR |
                      LibC::ICRNL | LibC::IXON)

    # Local flags - turn off canonical mode, echo, signals
    tios.c_lflag &= ~(LibC::ECHO | LibC::ECHONL | LibC::ICANON |
                      LibC::ISIG | LibC::IEXTEN)

    # Control flags - set 8 bit chars
    tios.c_cflag &= ~(LibC::CSIZE | LibC::PARENB)
    tios.c_cflag |= LibC::CS8

    # Control chars - set raw mode read behavior
    tios.c_cc[LibC::VMIN] = 1_u8  # minimum number of characters for read
    tios.c_cc[LibC::VTIME] = 0_u8 # timeout in deciseconds for read

    set_attrs(tios)
  end

  # Restores original terminal attributes saved during enable_raw_mode.
  #
  # Safe to call even if enable_raw_mode was never called (no-op).
  def restore
    @original.try(&->set_attrs(LibC::Termios))
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
