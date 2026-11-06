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
  @closed = Atomic(Bool).new(false)

  {% if flag?(:win32) %}
    @console_input : System::Console::Input
    @input_readiness : System::Console::ReadinessLease?
    @input_readiness_lock = Mutex.new
  {% end %}

  getter infd : IO::FileDescriptor::Handle
  getter outfd : IO::FileDescriptor::Handle

  # Creates a new terminal backend, opening `/dev/tty` for I/O.
  #
  # Raises `IO::Error` if the TTY cannot be opened.
  {% if flag?(:win32) %}
    def initialize
      @tty = TTY.new
      @infd = @tty.infd
      @outfd = @tty.outfd
      initialized = false
      begin
        @termios = Termios.new(@infd, @outfd)
        @console_input = System::Console::Input.new(@infd, @outfd)
        initialized = true
      ensure
        @tty.close rescue nil unless initialized
      end
    end
  {% else %}
    def initialize
      @tty = TTY.new
      @termios = Termios.new(@tty.outfd)
      @infd = @tty.infd
      @outfd = @tty.outfd
    end
  {% end %}

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
    {% if flag?(:win32) %}
      restore_console_mode
    {% else %}
      @termios.restore
      @raw_mode_enabled = false
    {% end %}
  end

  # Returns whether raw mode is currently enabled.
  def raw_mode? : Bool
    @raw_mode_enabled
  end

  # Writes data to the terminal output.
  def write(data : String)
    @tty.write(data)
  end

  # Writes raw bytes to the terminal output.
  def write(data : Bytes)
    @tty.write(data)
  end

  # Flushes the output buffer to the terminal.
  def flush
    @tty.flush
  end

  # Reads data from the terminal into the provided buffer.
  #
  # Returns the number of bytes read, or 0 on EOF or for an empty buffer.
  # Raises `IO::Error` on read failure.
  def read(buffer : Bytes) : Int32
    {% if flag?(:win32) %}
      raise IO::Error.new("Terminal backend is closed") if @closed.get
      return 0 if buffer.empty?

      loop do
        count = @console_input.read(buffer)
        return count if count > 0
        lease = @input_readiness_lock.synchronize do
          raise IO::Error.new("Terminal backend is closed") if @closed.get
          if current = @input_readiness
            current.rearm
            current
          else
            @input_readiness = System::Console::ReadinessLease.new(@infd)
          end
        end
        status = lease.wait(nil)
        raise lease.worker_error if lease.worker_failed?
        raise IO::Error.new("Terminal backend is closed") if @closed.get
        unless status == System::Console::ReadinessLease::Status::Ready
          raise IO::Error.new("Unexpected console input readiness status: #{status}")
        end
      end
    {% else %}
      loop do
        bytes_read = LibC.read(@infd, buffer, buffer.size)
        if bytes_read >= 0
          return bytes_read.to_i32
        end
        # bytes_read < 0: check errno
        if Errno.value == Errno::EINTR
          next # Retry on signal interruption
        end
        raise IO::Error.from_errno("read failed")
      end
    {% end %}
  end

  # Returns the terminal size as {width, height}.
  #
  # Uses the TIOCGWINSZ ioctl to query the terminal dimensions.
  # Raises `IO::Error` if the size cannot be determined.
  def size : {Int32, Int32}
    {% if flag?(:win32) %}
      if System::Console::C.GetConsoleScreenBufferInfo(LibC::HANDLE.new(@outfd), out info) == 0
        raise IO::Error.from_winerror("GetConsoleScreenBufferInfo")
      end
      {info.window.right.to_i32 - info.window.left.to_i32 + 1,
       info.window.bottom.to_i32 - info.window.top.to_i32 + 1}
    {% else %}
      winsize = uninitialized LibC::Winsize
      if LibC.ioctl(@outfd, LibC::TIOCGWINSZ, pointerof(winsize)) == -1
        raise IO::Error.from_errno("ioctl TIOCGWINSZ failed")
      end
      {winsize.ws_col.to_i32, winsize.ws_row.to_i32}
    {% end %}
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
  # Updates raw_mode_enabled tracking based on whether mode is raw.
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
    {% if flag?(:win32) %}
      @tty.flush
    {% end %}
    @termios.set_mode(mode)
    # Raw mode is represented by the zero-value flags state.
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
    {% if flag?(:win32) %}
      restore_console_mode(previous || Terminal::Mode.raw)
    {% else %}
      set_mode(previous || Terminal::Mode.raw)
    {% end %}
  end

  # Closes the terminal backend, disabling raw mode and closing TTY.
  def close
    return unless @closed.compare_and_set(false, true)[1]

    restore_error = nil.as(Exception?)
    {% if flag?(:win32) %}
      begin
        @input_readiness_lock.synchronize do
          if lease = @input_readiness
            begin
              lease.close
            ensure
              @input_readiness = nil if lease.closed?
            end
          end
        end
      rescue error
        if @input_readiness
          @closed.set(false)
          raise error
        end
        restore_error ||= error
      end
    {% end %}
    begin
      {% if flag?(:win32) %}
        restore_console_mode
      {% else %}
        disable_raw_mode
      {% end %}
    rescue ex
      restore_error ||= ex
    end

    begin
      @tty.close
    rescue error
      # Earlier cleanup failures take precedence, but descriptor closure is always attempted.
      restore_error ||= error
    end

    raise restore_error if restore_error
  end

  {% if flag?(:win32) %}
    private def restore_console_mode(mode : Terminal::Mode? = nil) : Nil
      error : Exception? = nil
      begin
        @tty.flush
      rescue ex
        error = ex
      end
      begin
        if mode
          @termios.set_mode(mode)
          @raw_mode_enabled = mode.value == 0
        else
          @termios.restore
          @raw_mode_enabled = false
        end
      rescue ex
        error ||= ex
      end
      raise error if error
    end
  {% end %}
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
