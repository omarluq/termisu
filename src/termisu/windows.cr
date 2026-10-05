{% if flag?(:win32) %}
  # Windows console backend. Loaded after the POSIX classes it reopens, so
  # each method here replaces its POSIX body, which is then never compiled.
  #
  # The console runs in VT mode (`ENABLE_VIRTUAL_TERMINAL_INPUT`), so key
  # presses, mouse reports and bracketed paste arrive as the same escape
  # sequences the POSIX parser already handles. They arrive as KEY_EVENT
  # records, read only once a record is known to be waiting, so nothing is
  # ever pulled off the console while a child process (an editor) owns it.
  module Termisu::System::Console
    lib C
      struct Coord
        x : Int16
        y : Int16
      end

      struct SmallRect
        left : Int16
        top : Int16
        right : Int16
        bottom : Int16
      end

      struct ScreenBufferInfo
        size : Coord
        cursor_position : Coord
        attributes : UInt16
        window : SmallRect
        maximum_window_size : Coord
      end

      # KEY_EVENT_RECORD. INPUT_RECORD's event field is a union; only key
      # events are read, and every other member is no larger than this one.
      struct KeyEventRecord
        key_down : LibC::BOOL
        repeat_count : UInt16
        virtual_key_code : UInt16
        virtual_scan_code : UInt16
        unicode_char : UInt16
        control_key_state : LibC::DWORD
      end

      struct InputRecord
        event_type : UInt16
        key_event : KeyEventRecord
      end

      KEY_EVENT = 0x0001_u16

      ENABLE_EXTENDED_FLAGS  = 0x0080_u32
      ENABLE_QUICK_EDIT_MODE = 0x0040_u32

      fun GetConsoleScreenBufferInfo(handle : LibC::HANDLE, info : ScreenBufferInfo*) : LibC::BOOL
      fun GetNumberOfConsoleInputEvents(handle : LibC::HANDLE, count : LibC::DWORD*) : LibC::BOOL
      fun ReadConsoleInputW(handle : LibC::HANDLE, buffer : InputRecord*, length : LibC::DWORD, read : LibC::DWORD*) : LibC::BOOL
    end

    # Polled instead of waited on: the input source already sleeps between
    # empty polls, and a wait would block every fiber on this thread.
    POLL_STEP = 5.milliseconds

    def self.input_handle : LibC::HANDLE
      LibC.GetStdHandle(LibC::STD_INPUT_HANDLE)
    end

    def self.input_mode : UInt32
      if LibC.GetConsoleMode(input_handle, out mode) == 0
        raise IO::Error.from_winerror("GetConsoleMode")
      end
      mode
    end

    def self.input_mode=(value : UInt32) : Nil
      if LibC.SetConsoleMode(input_handle, value) == 0
        raise IO::Error.from_winerror("SetConsoleMode")
      end
    end

    # The visible window, not the scrollback buffer: {columns, rows}.
    def self.size : {Int32, Int32}
      if C.GetConsoleScreenBufferInfo(LibC.GetStdHandle(LibC::STD_OUTPUT_HANDLE), out info) == 0
        raise IO::Error.from_winerror("GetConsoleScreenBufferInfo")
      end
      w = info.window
      {(w.right - w.left + 1).to_i32, (w.bottom - w.top + 1).to_i32}
    end

    @@pending = IO::Memory.new
    @@high_surrogate : UInt16?

    # Reads up to `buffer.size` bytes of typed input, waiting for some.
    def self.read(buffer : Bytes) : Int32
      wait
      @@pending.read(buffer)
    end

    # True once input is buffered, waiting at most *timeout* (forever when nil).
    def self.wait(timeout : Time::Span? = nil) : Bool
      deadline = timeout.try { |t| Time.instant + t }
      loop do
        return true if @@pending.pos < @@pending.size || pump
        return false if deadline && Time.instant >= deadline
        sleep POLL_STEP
      end
    end

    # Moves every waiting KEY_EVENT character into `@@pending` and drops the
    # other records (focus, menu, key-up), which would otherwise keep the
    # handle signalled with nothing to read.
    private def self.pump : Bool
      handle = input_handle
      return false if C.GetNumberOfConsoleInputEvents(handle, out count) == 0 || count == 0

      records = Slice.new(count.to_i32, C::InputRecord.new)
      return false if C.ReadConsoleInputW(handle, records, count, out got) == 0

      units = [] of UInt16
      if high = @@high_surrogate
        units << high
        @@high_surrogate = nil
      end
      records[0, got.to_i32].each do |record|
        next unless record.event_type == C::KEY_EVENT
        key = record.key_event
        next if key.key_down == 0 || key.unicode_char == 0
        key.repeat_count.clamp(1_u16, UInt16::MAX).times { units << key.unicode_char }
      end
      if (last = units.last?) && last & 0xFC00 == 0xD800
        @@high_surrogate = units.pop
      end
      return false if units.empty?

      # Only called once `@@pending` is drained, so it is replaced, not appended to.
      @@pending = IO::Memory.new(String.from_utf16(Slice.new(units.to_unsafe, units.size)))
      true
    end
  end

  # Termios: the same modes as console-mode bits on the input handle. The
  # output handle needs nothing; the stdlib already put STDOUT in VT mode.
  class Termisu::Termios
    @original_mode : UInt32?

    def set_mode(mode : Terminal::Mode)
      orig = @original_mode ||= System::Console.input_mode

      bits = orig & ~(LibC::ENABLE_LINE_INPUT | LibC::ENABLE_ECHO_INPUT |
                      LibC::ENABLE_PROCESSED_INPUT | LibC::ENABLE_VIRTUAL_TERMINAL_INPUT).to_u32
      if mode.canonical?
        bits |= LibC::ENABLE_LINE_INPUT
        # The console rejects echo without line input.
        bits |= LibC::ENABLE_ECHO_INPUT if mode.echo?
      else
        # Quick Edit would swallow the mouse reports a TUI asks for.
        bits = (bits | System::Console::C::ENABLE_EXTENDED_FLAGS) & ~System::Console::C::ENABLE_QUICK_EDIT_MODE
        bits |= LibC::ENABLE_VIRTUAL_TERMINAL_INPUT
      end
      bits |= LibC::ENABLE_PROCESSED_INPUT if mode.signals?

      System::Console.input_mode = bits.to_u32
      @current_mode = mode
    end

    def restore
      @original_mode.try { |orig| System::Console.input_mode = orig }
      @current_mode = nil
    end
  end

  class Termisu::TTY
    # No `/dev/tty` on Windows: the process's own console is used through
    # STDIN/STDOUT, so a TUI there needs both left unredirected.
    # 0 and 1 are the CRT descriptors; nothing on Windows reads them as fds.
    def initialize
      @out = STDOUT
      @outfd = 1
      @infd = 0
      @owns_input_fd = false
    end

    private def close_output_fd
    end

    private def close_input_fd(fd : Int32)
    end
  end

  class Termisu::Reader
    private def check_fd_readable(timeout_sec : Int32 = 0, timeout_usec : Int32 = 0) : Bool
      System::Console.wait(timeout_sec.seconds + timeout_usec.microseconds)
    end

    private def fill_buffer : Bool
      @buffer_pos = 0
      @buffer_len = System::Console.read(@buffer)
      true
    end
  end

  class Termisu::Terminal::Backend
    def read(buffer : Bytes) : Int32
      System::Console.read(buffer)
    end

    def size : {Int32, Int32}
      System::Console.size
    end
  end

  # No SIGWINCH: the poll interval alone picks up a resize.
  class Termisu::Event::Source::Resize
    private def install_signal_handler(wake : Channel(Nil), run_state : RunState) : Nil
    end

    private def install_inactive_signal_handler : Nil
    end
  end

  # Reachable only through `SystemTimer`, which Windows never builds (see
  # below); kept compiling without binding a `poll(2)` that is not there.
  class Termisu::Event::Poller::Poll
    private def poll_with_eintr(timeout_ms : Int32) : Int32
      raise NotImplementedError.new("poll(2) on Windows")
    end
  end

  class Termisu
    # No kernel timer is bound on Windows; the sleep-based timer stands in.
    def enable_system_timer(interval : Time::Span = 16.milliseconds) : self
      enable_timer(interval)
    end
  end
{% end %}
