# Low-level terminal I/O combining TTY and Termios state management.
#
# Provides basic terminal operations, managing both the underlying
# TTY file descriptors and terminal attributes (mode control).
# Used internally by Terminal for I/O operations.
#
# Example:
# ```
# backend = Termisu::Terminal::Backend.new
# backend.enable_raw_mode
# backend.write("Hello, terminal!")
# backend.flush
# backend.close
#
# # Or use mode switching:
# backend.set_mode(Terminal::Mode.cooked)
# backend.with_mode(Terminal::Mode.password) { gets }
# ```
class Termisu::Terminal::Backend
  @tty : TTY
  @termios : Termios
  @raw_mode_enabled : Bool = false

  getter infd : Int32
  getter outfd : Int32

  # Creates a new terminal backend, opening `/dev/tty` for I/O.
  #
  # Raises `IO::Error` if the TTY cannot be opened.
  def initialize
    @tty = TTY.new
    @termios = Termios.new(@tty.outfd)
    @infd = @tty.infd
    @outfd = @tty.outfd
  end

  # Enables raw mode for the terminal.
  #
  # Raw mode disables input processing, canonical mode, echo, and signals,
  # allowing direct character-by-character input without line buffering.
  #
  # This method is idempotent - calling it multiple times has no effect
  # if raw mode is already enabled.
  def enable_raw_mode
    return if @raw_mode_enabled
    @termios.enable_raw_mode
    @raw_mode_enabled = true
  end

  # Disables raw mode, restoring original terminal attributes.
  #
  # This method is idempotent - calling it multiple times has no effect
  # if raw mode is already disabled.
  def disable_raw_mode
    return unless @raw_mode_enabled
    @termios.restore
    @raw_mode_enabled = false
  end

  # Returns whether raw mode is currently enabled.
  def raw_mode? : Bool
    @raw_mode_enabled
  end

  # Writes data to the terminal output.
  def write(data : String)
    @tty.write(data)
  end

  # Flushes the output buffer to the terminal.
  def flush
    @tty.flush
  end

  # Reads data from the terminal into the provided buffer.
  #
  # Returns the number of bytes read, or 0 on EOF.
  # Raises `IO::Error` on read failure.
  def read(buffer : Bytes) : Int32
    bytes_read = LibC.read(@infd, buffer, buffer.size)
    raise IO::Error.from_errno("read failed") if bytes_read < 0
    bytes_read.to_i32
  end

  # Returns the terminal size as {width, height}.
  #
  # Uses the TIOCGWINSZ ioctl to query the terminal dimensions.
  # Raises `IO::Error` if the size cannot be determined.
  def size : {Int32, Int32}
    winsize = uninitialized LibC::Winsize
    if LibC.ioctl(@outfd, LibC::TIOCGWINSZ, pointerof(winsize)) == -1
      raise IO::Error.from_errno("ioctl TIOCGWINSZ failed")
    end
    {winsize.ws_col.to_i32, winsize.ws_row.to_i32}
  end

  # Executes a block with raw mode enabled, ensuring cleanup.
  #
  # Example:
  # ```
  # backend.with_raw_mode do
  #   # Raw mode operations here
  # end
  # # Raw mode automatically disabled
  # ```
  def with_raw_mode(&)
    enable_raw_mode
    yield
  ensure
    disable_raw_mode
  end

  # --- Terminal Mode API ---

  # Sets terminal to specific mode using Terminal::Mode flags.
  #
  # Updates raw_mode_enabled tracking based on whether mode is raw
  # (none? means no flags set = raw mode).
  #
  # Parameters:
  # - mode: Terminal::Mode flags specifying desired behavior
  #
  # Example:
  # ```
  # backend.set_mode(Terminal::Mode.cooked) # Shell-out mode
  # backend.set_mode(Terminal::Mode.raw)    # Full TUI control
  # ```
  # ameba:disable Naming/AccessorMethodName
  def set_mode(mode : Terminal::Mode)
    @termios.set_mode(mode)
    # Raw mode = no flags set (value 0). Can't use none? due to @[Flags] semantics.
    @raw_mode_enabled = mode.value == 0
  end

  # Returns the current terminal mode, or nil if not yet set.
  #
  # Delegates to underlying Termios instance.
  def current_mode : Terminal::Mode?
    @termios.current_mode
  end

  # Executes a block with specific terminal mode, restoring previous mode after.
  #
  # This is the RAII pattern for safe mode switching. The previous mode
  # is always restored, even if the block raises an exception.
  #
  # Parameters:
  # - mode: Terminal::Mode to use within the block
  #
  # Example:
  # ```
  # backend.with_mode(Terminal::Mode.cooked) do
  #   system("vim file.txt")
  # end
  # # Previous mode automatically restored
  # ```
  def with_mode(mode : Terminal::Mode, &)
    previous = current_mode
    set_mode(mode)
    yield
  ensure
    # Restore previous mode, or raw mode if no previous mode was set
    set_mode(previous || Terminal::Mode.raw)
  end

  # Closes the terminal backend, disabling raw mode and closing TTY.
  def close
    disable_raw_mode
    @tty.close
  end
end

# Add Winsize struct to LibC if not already defined
lib LibC
  {% unless LibC.has_constant?(:Winsize) %}
    struct Winsize
      ws_row : UInt16
      ws_col : UInt16
      ws_xpixel : UInt16
      ws_ypixel : UInt16
    end
  {% end %}

  {% unless LibC.has_constant?(:TIOCGWINSZ) %}
    {% if flag?(:linux) %}
      TIOCGWINSZ = 0x5413
    {% elsif flag?(:darwin) %}
      TIOCGWINSZ = 0x40087468
    {% elsif flag?(:freebsd) || flag?(:openbsd) %}
      TIOCGWINSZ = 0x40087468
    {% else %}
      TIOCGWINSZ = 0x5413
    {% end %}
  {% end %}

  fun ioctl(fd : Int32, request : UInt64, ...) : Int32
end
