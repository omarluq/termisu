require "spec"

{% if flag?(:win32) %}
  # Run only in a disposable idle console; these probes inject and consume input.
  require "../../../src/termisu"
  require "../../../src/termisu/time_compat"

  alias WindowsConsole = Termisu::System::Console::C

  module WindowsConsoleProbe
    extend self

    @[Link("kernel32")]
    lib Native
      HANDLE_FLAG_INHERIT     = 0x0001_u32
      ENABLE_PROCESSED_OUTPUT = 0x0001_u32

      fun CreateConsoleScreenBuffer(access : LibC::DWORD, share : LibC::DWORD,
                                    attributes : LibC::SECURITY_ATTRIBUTES*, flags : LibC::DWORD, reserved : Void*) : LibC::HANDLE
      fun ReadConsoleOutputCharacterW(handle : LibC::HANDLE, characters : UInt16*, length : LibC::DWORD,
                                     origin : WindowsConsole::Coord, read : LibC::DWORD*) : LibC::BOOL
      fun SetConsoleScreenBufferSize(handle : LibC::HANDLE, size : WindowsConsole::Coord) : LibC::BOOL
      fun SetConsoleWindowInfo(handle : LibC::HANDLE, absolute : LibC::BOOL, window : WindowsConsole::SmallRect*) : LibC::BOOL
      fun GetHandleInformation(handle : LibC::HANDLE, flags : LibC::DWORD*) : LibC::BOOL
      fun CreateEventW(attributes : LibC::SECURITY_ATTRIBUTES*, manual_reset : LibC::BOOL,
                       initial_state : LibC::BOOL, name : LibC::LPWSTR) : LibC::HANDLE
      fun SetEvent(handle : LibC::HANDLE) : LibC::BOOL
      fun WaitForMultipleObjects(count : LibC::DWORD, handles : LibC::HANDLE*,
                                 wait_all : LibC::BOOL, milliseconds : LibC::DWORD) : LibC::DWORD
    end

    def check(result : LibC::BOOL, operation : String) : Nil
      raise IO::Error.from_winerror(operation) if result == 0
    end

    def open_console(name : String) : LibC::HANDLE
      path = "#{name}\0".to_utf16
      handle = LibC.CreateFileW(path, LibC::GENERIC_READ | LibC::GENERIC_WRITE,
        LibC::FILE_SHARE_READ | LibC::FILE_SHARE_WRITE, nil, LibC::OPEN_EXISTING, 0_u32, nil)
      if handle == LibC::INVALID_HANDLE_VALUE
        raise IO::Error.from_winerror("CreateFileW(#{name}); an attached console is required")
      end
      handle
    end

    def with_screen_buffer(&) : Nil
      handle = Native.CreateConsoleScreenBuffer(LibC::GENERIC_READ | LibC::GENERIC_WRITE,
        LibC::FILE_SHARE_READ | LibC::FILE_SHARE_WRITE, nil, 1_u32, nil)
      raise IO::Error.from_winerror("CreateConsoleScreenBuffer") if handle == LibC::INVALID_HANDLE_VALUE
      with_handle(handle) { |output| yield output }
    end

    def screen_text(output : LibC::HANDLE, count : Int32) : Array(UInt16)
      characters = Slice(UInt16).new(count)
      check Native.ReadConsoleOutputCharacterW(output, characters, count.to_u32, WindowsConsole::Coord.new, out read),
        "ReadConsoleOutputCharacterW"
      read.should eq(count.to_u32)
      characters.to_a
    end

    def with_handle(handle : LibC::HANDLE, &) : Nil
      error : Exception? = nil
      begin
        yield handle
      rescue ex
        error = ex
      ensure
        if LibC.CloseHandle(handle) == 0
          close_error = IO::Error.from_winerror("CloseHandle")
          error ||= close_error
        end
      end
      raise error if error
    end

    def with_console(&) : Nil
      with_handle(open_console("CONIN$")) do |input|
        with_handle(open_console("CONOUT$")) do |output|
          yield input, output
        end
      end
    end

    def mode(handle : LibC::HANDLE) : UInt32
      check LibC.GetConsoleMode(handle, out value), "GetConsoleMode"
      value
    end

    def with_modes(input : LibC::HANDLE, output : LibC::HANDLE, &) : Nil
      snapshots = [{input, mode(input)}, {output, mode(output)}]
      error : Exception? = nil
      begin
        yield
      rescue ex
        error = ex
      ensure
        snapshots.reverse_each do |handle, original|
          if LibC.SetConsoleMode(handle, original) == 0
            restore_error = IO::Error.from_winerror("SetConsoleMode(restore)")
            error ||= restore_error
          end
        end
      end
      raise error if error
    end

    def event : LibC::HANDLE
      handle = Native.CreateEventW(nil, 1, 0, nil)
      raise IO::Error.from_winerror("CreateEventW") if handle.null?
      handle
    end

    def key(unit : UInt16, virtual_key : UInt16 = 0, *, repeats : UInt16 = 1, state : UInt32 = 0) : WindowsConsole::InputRecord
      record = WindowsConsole::InputRecord.new
      record.event_type = WindowsConsole::KEY_EVENT
      event = WindowsConsole::KeyEventRecord.new
      event.key_down = 1
      event.repeat_count = repeats
      event.virtual_key_code = virtual_key
      event.unicode_char = unit
      event.control_key_state = state
      record.key_event = event
      record
    end

    def mouse(buttons : UInt32, flags : UInt32 = 0, state : UInt32 = 0, x : Int16 = 4, y : Int16 = 6) : WindowsConsole::InputRecord
      event = WindowsConsole::MouseEventRecord.new
      event.position = WindowsConsole::Coord.new(x: x, y: y)
      event.button_state, event.control_key_state, event.event_flags = buttons, state, flags
      record = WindowsConsole::InputRecord.new
      record.event_type = WindowsConsole::MOUSE_EVENT
      record.key_event = event.unsafe_as(WindowsConsole::KeyEventRecord)
      record
    end

    class RetainedInputSource < Termisu::Event::Source::Input
      def seed_lease(lease : Termisu::System::Console::ReadinessLease) : Nil
        @lease = lease
      end
    end

    class FailedWideOutput < Termisu::System::Console::Output
      getter failure = IO::Error.new("injected wide output failure")

      private def write_wide(handle : LibC::HANDLE, wide : Slice(UInt16)) : Nil
        raise @failure
      end
    end

    class FailedOutputMode < Termisu::Termios
      getter failure = IO::Error.new("injected console output mode failure")
      @fail_output = true

      private def apply_console_mode(fd : IO::FileDescriptor::Handle, mode : UInt32) : Nil
        if fd == @output_fd && @fail_output
          @fail_output = false
          raise @failure
        end
        super
      end
    end

    def write_keys(input : LibC::HANDLE, unit : UInt16, *, count : Int32 = 1) : Nil
      # VT translation handles each record once, ignoring its legacy repeat count.
      records = Slice(WindowsConsole::InputRecord).new(count) { key(unit) }
      check WindowsConsole.WriteConsoleInputW(input, records, count.to_u32, out written), "WriteConsoleInputW(keys)"
      written.should eq(count.to_u32)
      peek = Slice(WindowsConsole::InputRecord).new(count + 32) { WindowsConsole::InputRecord.new }
      read = Termisu::System::Console.read_records(input, peek, remove: false)
      characters = peek[0, read].sum do |record|
        if record.event_type == WindowsConsole::KEY_EVENT && record.key_event.key_down != 0 && record.key_event.unicode_char == unit
          record.key_event.repeat_count.to_i32
        else
          0
        end
      end
      characters.should eq(count)
    end

    def receive(output : Channel(Termisu::Event::Any)) : Termisu::Event::Any
      select
      when event = output.receive
        event
      when timeout(2.seconds)
        raise "Timed out receiving native input/timer event"
      end
    end

    def key_event(event : Termisu::Event::Any?) : Termisu::Event::Key
      event.should be_a(Termisu::Event::Key)
      event.as(Termisu::Event::Key)
    end

    class BufferedInput < Termisu::System::Console::Input
      def seed(records : Array(WindowsConsole::InputRecord)) : Nil
        raise "oversized fixture batch" if records.size > @records.size
        records.each_with_index { |record, index| @records[index] = record }
        @record_pos = 0
        @record_count = records.size
      end
    end

    class FailedWaitLease < Termisu::System::Console::ReadinessLease
      getter failure = IO::Error.new("injected readiness wait failure")

      private def wait_handles(_handles : Array(LibC::HANDLE)) : UInt32
        raise @failure
      end
    end

    class FailedNotificationLease < Termisu::System::Console::ReadinessLease
      getter failure = IO::Error.new("injected readiness notification failure")

      private def publish(_status : Status) : Nil
        raise @failure
      end
    end

    class FailedCancellationLease < Termisu::System::Console::ReadinessLease
      getter failure = IO::Error.new("injected cancellation failure")
      @fail_once = true

      private def signal_cancellation : Nil
        if @fail_once
          @fail_once = false
          raise @failure
        end
        super
      end
    end

    class PersistentCancellationLease < Termisu::System::Console::ReadinessLease
      getter failure = IO::Error.new("injected persistent cancellation failure")
      property reject = true

      private def signal_cancellation : Nil
        raise @failure if @reject
        super
      end
    end

    class CancellationInputSource < Termisu::Event::Source::Input
      property injected_lease : Termisu::System::Console::ReadinessLease?

      private def create_readiness_lease : Termisu::System::Console::ReadinessLease
        @injected_lease || super
      end
    end

    class UnconfirmedJoinLease < Termisu::System::Console::ReadinessLease
      @fail_once = true

      private def join_worker : Nil
        if @fail_once
          @fail_once = false
          raise IO::Error.new("injected unconfirmed join")
        end
        super
      end
    end
  end

  describe Termisu::System::Console do
    it "matches the x64 Windows SDK record layouts without truncating handles" do
      sizeof(LibC::HANDLE).should eq(8)
      sizeof(LibC::UIntPtrT).should eq(sizeof(LibC::HANDLE))
      sizeof(WindowsConsole::KeyEventRecord).should eq(16)
      sizeof(WindowsConsole::MouseEventRecord).should eq(sizeof(WindowsConsole::KeyEventRecord))
      offsetof(WindowsConsole::MouseEventRecord, @button_state).should eq(4)
      offsetof(WindowsConsole::MouseEventRecord, @control_key_state).should eq(8)
      offsetof(WindowsConsole::MouseEventRecord, @event_flags).should eq(12)
      sizeof(WindowsConsole::InputRecord).should eq(20)
      offsetof(WindowsConsole::InputRecord, @key_event).should eq(4)
      sizeof(WindowsConsole::ScreenBufferInfo).should eq(22)
    end

    it "parses native mouse records and VT mouse bytes through the shared parser" do
      WindowsConsoleProbe.with_console do |input, output|
        WindowsConsoleProbe.with_modes(input, output) do
          mode = WindowsConsoleProbe.mode(input) & ~LibC::ENABLE_VIRTUAL_TERMINAL_INPUT.to_u32
          WindowsConsoleProbe.check LibC.SetConsoleMode(input, mode), "SetConsoleMode(legacy records)"
          records = [WindowsConsoleProbe.mouse(1, state: 0x1F_u32),
                     WindowsConsoleProbe.mouse(1, WindowsConsole::MOUSE_MOVED),
                     WindowsConsoleProbe.mouse(3), WindowsConsoleProbe.mouse(2), WindowsConsoleProbe.mouse(0),
                     WindowsConsoleProbe.mouse(4), WindowsConsoleProbe.mouse(0),
                     WindowsConsoleProbe.mouse(8), WindowsConsoleProbe.mouse(0),
                     WindowsConsoleProbe.mouse(16), WindowsConsoleProbe.mouse(0),
                     WindowsConsoleProbe.mouse(0x00780000_u32, WindowsConsole::MOUSE_WHEELED),
                     WindowsConsoleProbe.mouse(0xFF880000_u32, WindowsConsole::MOUSE_WHEELED),
                     WindowsConsoleProbe.mouse(0x00F00000_u32, WindowsConsole::MOUSE_HWHEELED),
                     WindowsConsoleProbe.mouse(0xFF880000_u32, WindowsConsole::MOUSE_HWHEELED),
                     WindowsConsoleProbe.mouse(0, WindowsConsole::MOUSE_MOVED),
                     WindowsConsoleProbe.mouse(1, WindowsConsole::DOUBLE_CLICK),
                     WindowsConsoleProbe.mouse(1, WindowsConsole::DOUBLE_CLICK), WindowsConsoleProbe.mouse(0)]
          "\e[<2;9;10M".each_byte { |byte| records << WindowsConsoleProbe.key(byte.to_u16) }
          WindowsConsoleProbe.check WindowsConsole.WriteConsoleInputW(input, records.to_unsafe, records.size.to_u32, out written),
            "WriteConsoleInputW(mouse/VT records)"
          written.should eq(records.size.to_u32)
          reader = Termisu::Reader.new(input.address)
          begin
            parser = Termisu::Input::Parser.new(reader)
            buttons = ["Left", "Left", "Right", "Release", "Release", "Middle", "Release",
                       "Button4", "Release", "Button5", "Release", "WheelUp", "WheelDown",
                       "WheelRight", "WheelRight", "WheelLeft", "Release", "Left", "Left", "Release", "Right"]
            buttons.each_with_index do |button, index|
              event = parser.poll_event(1000)
              event.should be_a(Termisu::Event::Mouse)
              mouse = event.as(Termisu::Event::Mouse)
              mouse.button.to_s.should eq(button)
              {mouse.x, mouse.y}.should eq(index == buttons.size - 1 ? {9, 10} : {5, 7})
              mouse.motion?.should eq(index == 1 || index == 16)
              if index == 0
                mouse.shift?.should be_true
                mouse.alt?.should be_true
                mouse.ctrl?.should be_true
              end
            end
          ensure
            reader.close
          end
        end
      end
    end

    it "accumulates high-resolution wheel deltas without expanding repeated reports" do
      WindowsConsoleProbe.with_console do |input, _output|
        decoder = WindowsConsoleProbe::BufferedInput.new(input.address)
        records = Array.new(8) { WindowsConsoleProbe.mouse(0x001E0000_u32, WindowsConsole::MOUSE_WHEELED) }
        decoder.seed(records)
        expected = "\e[<64;5;7M" * 2
        bytes = Bytes.new(expected.bytesize)
        decoder.read(bytes).should eq(bytes.size)
        String.new(bytes).should eq(expected)
        decoder.clear
        decoder.seed([WindowsConsoleProbe.mouse(0x80000000_u32, WindowsConsole::MOUSE_HWHEELED)])
        one = Bytes.new(1)
        decoder.read(one).should eq(1)
        decoder.@repeats.should be <= 273
        decoder.@pending.bytesize.should be < 32
        decoder.clear
        decoder.buffered?.should be_false
      end
    end

    it "maps legacy mouse coordinates to the borrowed viewport origin" do
      WindowsConsoleProbe.with_console do |input, output|
        WindowsConsoleProbe.with_modes(input, output) do
          WindowsConsoleProbe.with_screen_buffer do |screen|
            WindowsConsoleProbe.check WindowsConsole.GetConsoleScreenBufferInfo(screen, out info), "GetConsoleScreenBufferInfo"
            size = WindowsConsole::Coord.new(x: info.size.x, y: (info.size.y + 10).to_i16)
            WindowsConsoleProbe.check WindowsConsoleProbe::Native.SetConsoleScreenBufferSize(screen, size), "SetConsoleScreenBufferSize"
            window = info.window
            window.top += 5
            window.bottom += 5
            WindowsConsoleProbe.check WindowsConsoleProbe::Native.SetConsoleWindowInfo(screen, 1, pointerof(window)), "SetConsoleWindowInfo"
            mode = WindowsConsoleProbe.mode(input) & ~LibC::ENABLE_VIRTUAL_TERMINAL_INPUT.to_u32
            WindowsConsoleProbe.check LibC.SetConsoleMode(input, mode), "SetConsoleMode(legacy records)"
            record = WindowsConsoleProbe.mouse(1, x: window.left, y: window.top)
            WindowsConsoleProbe.check WindowsConsole.WriteConsoleInputW(input, pointerof(record), 1_u32, out written), "WriteConsoleInputW(mouse origin)"
            written.should eq(1_u32)
            reader = Termisu::Reader.new(input.address, output_fd: screen.address)
            begin
              event = Termisu::Input::Parser.new(reader).poll_event(1000)
              event.should be_a(Termisu::Event::Mouse)
              mouse = event.as(Termisu::Event::Mouse)
              {mouse.x, mouse.y}.should eq({1, 1})
            ensure
              reader.close
            end
          end
        end
      end
    end

    it "enables native mouse records only while public mouse tracking is active" do
      WindowsConsoleProbe.with_console do |input, output|
        WindowsConsoleProbe.with_modes(input, output) do
          term = Termisu.new
          begin
            (WindowsConsoleProbe.mode(input) & WindowsConsole::ENABLE_MOUSE_INPUT).should eq(0_u32)
            term.enable_mouse
            (WindowsConsoleProbe.mode(input) & WindowsConsole::ENABLE_MOUSE_INPUT).should_not eq(0_u32)
            term.@terminal.set_mode(Termisu::Terminal::Mode.raw)
            (WindowsConsoleProbe.mode(input) & WindowsConsole::ENABLE_MOUSE_INPUT).should_not eq(0_u32)
            term.disable_mouse
            (WindowsConsoleProbe.mode(input) & WindowsConsole::ENABLE_MOUSE_INPUT).should eq(0_u32)
          ensure
            term.close
          end
        end
      end
    end

    it "cleans a stopped source after transient cancellation failure and preserves the first error" do
      WindowsConsoleProbe.with_console do |input, _output|
        reader = Termisu::Reader.new(input.address)
        source = WindowsConsoleProbe::CancellationInputSource.new(reader, Termisu::Input::Parser.new(reader))
        lease = WindowsConsoleProbe::FailedCancellationLease.new(input.address)
        source.injected_lease = lease
        begin
          source.start(Channel(Termisu::Event::Any).new)
          Fiber.yield
          error = expect_raises(IO::Error, "injected cancellation failure") { source.stop }
          error.should be(lease.failure)
          lease.closed?.should be_true
          source.stop_required?.should be_false
          source.injected_lease = nil
          source.start(Channel(Termisu::Event::Any).new)
          source.stop
        ensure
          source.stop
          lease.close
          reader.close
        end
      end
    end

    it "retains unconfirmed source resources when cancellation keeps failing" do
      WindowsConsoleProbe.with_console do |input, _output|
        reader = Termisu::Reader.new(input.address)
        source = WindowsConsoleProbe::CancellationInputSource.new(reader, Termisu::Input::Parser.new(reader))
        lease = WindowsConsoleProbe::PersistentCancellationLease.new(input.address)
        source.injected_lease = lease
        begin
          source.start(Channel(Termisu::Event::Any).new)
          Fiber.yield
          error = expect_raises(IO::Error, "injected persistent cancellation failure") { source.stop }
          error.should be(lease.failure)
          lease.closed?.should be_false
          source.stop_required?.should be_true
          WindowsConsoleProbe.check WindowsConsoleProbe::Native.GetHandleInformation(lease.@input, out _), "GetHandleInformation(retained input)"
        ensure
          lease.reject = false
          source.stop
          lease.close
          reader.close
        end
      end
    end

    it "temporarily enables VT output and restores canonical output modes on failure" do
      WindowsConsoleProbe.with_screen_buffer do |handle|
        original = WindowsConsoleProbe.mode(handle) & ~0x000D_u32
        WindowsConsoleProbe.check LibC.SetConsoleMode(handle, original), "SetConsoleMode(no VT output)"
        sink = Termisu::System::Console::Output.new(handle.address)
        sink.write("\e[1;1HV".to_slice)
        sink.flush
        WindowsConsoleProbe.screen_text(handle, 1).should eq([0x56_u16])
        WindowsConsoleProbe.mode(handle).should eq(original)
        failed = WindowsConsoleProbe::FailedWideOutput.new(handle.address)
        failed.write("\e[1;1HX".to_slice)
        error = expect_raises(IO::Error, "injected wide output failure") { failed.flush }
        error.should be(failed.failure)
        WindowsConsoleProbe.mode(handle).should eq(original)
        failed.@buffer.size.should eq(0)
      end
    end

    it "renders nested canonical scopes without leaking escape sequences or changing the saved output mode" do
      WindowsConsoleProbe.with_console do |input, output|
        WindowsConsoleProbe.with_modes(input, output) do
          original = WindowsConsoleProbe.mode(output) & ~0x000D_u32
          WindowsConsoleProbe.check LibC.SetConsoleMode(output, original), "SetConsoleMode(no VT output)"
          term = Termisu.new
          begin
            term.with_mode(Termisu::Terminal::Mode.cooked, preserve_screen: true) do
              WindowsConsoleProbe.mode(output).should eq(original)
              term.with_mode(Termisu::Terminal::Mode.password, preserve_screen: true) do
                term.set_cell(0, 0, 'Z')
                term.render
                WindowsConsoleProbe.with_handle(WindowsConsoleProbe.open_console("CONOUT$")) do |active|
                  WindowsConsoleProbe.screen_text(active, 1).should eq([0x5A_u16])
                end
                WindowsConsoleProbe.mode(output).should eq(original)
              end
              WindowsConsoleProbe.mode(output).should eq(original)
            end
          ensure
            term.close
          end
          WindowsConsoleProbe.mode(output).should eq(original)
        end
      end
    end

    it "opens non-inheritable console handles independently of standard streams" do
      WindowsConsoleProbe.with_console do |input, output|
        input.should_not eq(LibC.GetStdHandle(LibC::STD_INPUT_HANDLE))
        output.should_not eq(LibC.GetStdHandle(LibC::STD_OUTPUT_HANDLE))
        {input, output}.each do |handle|
          WindowsConsoleProbe.mode(handle)
          WindowsConsoleProbe.check WindowsConsoleProbe::Native.GetHandleInformation(handle, out flags),
            "GetHandleInformation"
          (flags & WindowsConsoleProbe::Native::HANDLE_FLAG_INHERIT).should eq(0_u32)
        end
        WindowsConsoleProbe.check WindowsConsole.GetConsoleScreenBufferInfo(output, out info), "GetConsoleScreenBufferInfo"
        (info.window.right.to_i32 - info.window.left + 1).should be > 0
        (info.window.bottom.to_i32 - info.window.top + 1).should be > 0
      end
    end

    it "closes an acquired handle when a later acquisition or operation fails" do
      handle = WindowsConsoleProbe.open_console("CONIN$")
      expect_raises(Exception, "probe failure") do
        WindowsConsoleProbe.with_handle(handle) { raise "probe failure" }
      end
      result = WindowsConsoleProbe::Native.GetHandleInformation(handle, out _)
      error = LibC.GetLastError
      result.should eq(0)
      error.should eq(6_u32) # ERROR_INVALID_HANDLE
    end

    it "restores input and output modes even when the body raises" do
      WindowsConsoleProbe.with_console do |input, output|
        input_mode = WindowsConsoleProbe.mode(input)
        output_mode = WindowsConsoleProbe.mode(output)
        input_cp = LibC.GetConsoleCP
        output_cp = LibC.GetConsoleOutputCP
        expect_raises(Exception, "mode probe failure") do
          WindowsConsoleProbe.with_modes(input, output) do
            disabled = (LibC::ENABLE_LINE_INPUT | LibC::ENABLE_ECHO_INPUT |
                        LibC::ENABLE_PROCESSED_INPUT).to_u32 | WindowsConsole::ENABLE_QUICK_EDIT_MODE
            raw = (input_mode & ~disabled) | WindowsConsole::ENABLE_EXTENDED_FLAGS |
                  LibC::ENABLE_VIRTUAL_TERMINAL_INPUT.to_u32
            WindowsConsoleProbe.check LibC.SetConsoleMode(input, raw), "SetConsoleMode(input VT)"
            vt_output = output_mode | WindowsConsoleProbe::Native::ENABLE_PROCESSED_OUTPUT |
                        LibC::ENABLE_VIRTUAL_TERMINAL_PROCESSING.to_u32
            WindowsConsoleProbe.check LibC.SetConsoleMode(output, vt_output), "SetConsoleMode(output VT)"
            WindowsConsoleProbe.mode(input).should eq(raw)
            WindowsConsoleProbe.mode(output).should eq(vt_output)
            raise "mode probe failure"
          end
        end
        WindowsConsoleProbe.mode(input).should eq(input_mode)
        WindowsConsoleProbe.mode(output).should eq(output_mode)
        LibC.GetConsoleCP.should eq(input_cp)
        LibC.GetConsoleOutputCP.should eq(output_cp)
      end
    end

    it "waits on console and cancellation handles without consuming input" do
      WindowsConsoleProbe.with_console do |input, _output|
        WindowsConsoleProbe.with_handle(WindowsConsoleProbe.event) do |cancel|
          handles = [cancel, input]
          WindowsConsoleProbe.check WindowsConsole.GetNumberOfConsoleInputEvents(input, out before),
            "GetNumberOfConsoleInputEvents"
          result = WindowsConsoleProbe::Native.WaitForMultipleObjects(2_u32, handles, 0, 0_u32)
          if result == LibC::WAIT_FAILED
            raise IO::Error.from_winerror("WaitForMultipleObjects(console)")
          end
          {LibC::WAIT_TIMEOUT, LibC::WAIT_OBJECT_0 + 1_u32}.should contain(result)
          WindowsConsoleProbe.check WindowsConsoleProbe::Native.SetEvent(cancel), "SetEvent"
          WindowsConsoleProbe::Native.WaitForMultipleObjects(2_u32, handles, 0, 0_u32).should eq(LibC::WAIT_OBJECT_0)
          WindowsConsoleProbe.check WindowsConsole.GetNumberOfConsoleInputEvents(input, out after),
            "GetNumberOfConsoleInputEvents"
          after.should be >= before
        end
      end
    end

    it "cancels an idle native wait while cooperative fibers remain runnable" do
      WindowsConsoleProbe.with_handle(WindowsConsoleProbe.event) do |cancel|
        WindowsConsoleProbe.with_handle(WindowsConsoleProbe.event) do |idle|
          handles = [cancel, idle]
          started = Atomic(Bool).new(false)
          finished = Atomic(Bool).new(false)
          result = Atomic(UInt32).new(LibC::WAIT_FAILED)
          native_error = Atomic(UInt32).new(0_u32)
          worker = Thread.new do
            started.set(true)
            value = WindowsConsoleProbe::Native.WaitForMultipleObjects(2_u32, handles, 0, 5000_u32)
            native_error.set(LibC.GetLastError) if value == LibC::WAIT_FAILED
            result.set(value)
            finished.set(true)
          end
          begin
            deadline = monotonic_now + 2.seconds
            until started.get || monotonic_now >= deadline
              sleep 1.millisecond
            end
            started.get.should be_true
            heartbeat = Atomic(Bool).new(false)
            spawn { heartbeat.set(true) }
            sleep 10.milliseconds
            heartbeat.get.should be_true
            finished.get.should be_false
            WindowsConsoleProbe.check WindowsConsoleProbe::Native.SetEvent(cancel), "SetEvent"
            deadline = monotonic_now + 2.seconds
            until finished.get || monotonic_now >= deadline
              sleep 1.millisecond
            end
            finished.get.should be_true
            native_error.get.should eq(0_u32)
            result.get.should eq(LibC::WAIT_OBJECT_0)
          ensure
            # Join before close even on failure; the native wait has a finite guard.
            WindowsConsoleProbe::Native.SetEvent(cancel)
            worker.join
          end
        end
      end
    end

    it "calls the documented bounded NOWAIT record API without consuming input" do
      WindowsConsoleProbe.with_console do |input, _output|
        records = Slice(WindowsConsole::InputRecord).new(32) { WindowsConsole::InputRecord.new }
        WindowsConsoleProbe.check WindowsConsole.GetNumberOfConsoleInputEvents(input, out before),
          "GetNumberOfConsoleInputEvents"
        count = Termisu::System::Console.read_records(input, records, remove: false)
        count.should be >= 0
        count.should be <= records.size
        WindowsConsoleProbe.check WindowsConsole.GetNumberOfConsoleInputEvents(input, out after),
          "GetNumberOfConsoleInputEvents"
        after.should be >= before
      end
    end

    it "wakes a cooperative timed pipe reader from a synchronous native writer" do
      WindowsConsoleProbe.with_handle(WindowsConsoleProbe.event) do |cancel|
        reader, writer = IO.pipe(read_blocking: false, write_blocking: true)
        write_result = Atomic(Int32).new(-1)
        written = Atomic(UInt32).new(0_u32)
        native_error = Atomic(UInt32).new(0_u32)
        handles = [cancel]
        worker = Thread.new do
          result = WindowsConsoleProbe::Native.WaitForMultipleObjects(1_u32, handles, 0, 5000_u32)
          if result == LibC::WAIT_OBJECT_0
            byte = 1_u8
            result = LibC.WriteFile(LibC::HANDLE.new(writer.fd), pointerof(byte), 1_u32, out count, nil)
            native_error.set(LibC.GetLastError) if result == 0
            written.set(count)
            write_result.set(result)
          else
            native_error.set(result == LibC::WAIT_FAILED ? LibC.GetLastError : result)
          end
        end
        begin
          heartbeat = Atomic(Bool).new(false)
          spawn { heartbeat.set(true) }
          reader.read_timeout = 10.milliseconds
          expect_raises(IO::TimeoutError) { reader.read_byte }
          heartbeat.get.should be_true
          write_result.get.should eq(-1)
          WindowsConsoleProbe.check WindowsConsoleProbe::Native.SetEvent(cancel), "SetEvent"
          reader.read_timeout = 2.seconds
          reader.read_byte.should eq(1_u8)
        ensure
          WindowsConsoleProbe::Native.SetEvent(cancel)
          worker.join
          reader.close
          writer.close
        end
        native_error.get.should eq(0_u32)
        write_result.get.should eq(1)
        written.get.should eq(1_u32)
      end
    end

    it "joins idle production readiness runs before closing all five owned handles" do
      WindowsConsoleProbe.with_console do |input, _output|
        WindowsConsoleProbe.check WindowsConsole.GetNumberOfConsoleInputEvents(input, out before),
          "GetNumberOfConsoleInputEvents"
        before.should eq(0_u32)
        records = Slice(WindowsConsole::InputRecord).new(1) { WindowsConsole::InputRecord.new }
        Termisu::System::Console.read_records(input, records).should eq(0)
        8.times do
          lease = Termisu::System::Console::ReadinessLease.new(input.address)
          handles = [lease.@input, lease.@cancel, lease.@rearm, lease.@writer,
                     LibC::HANDLE.new(lease.@reader.not_nil!.fd)]
          begin
            lease.wait(monotonic_now + 20.milliseconds).should be_nil
            spawn do
              sleep 1.millisecond
              lease.cancel
            end
            lease.wait(nil).should eq(Termisu::System::Console::ReadinessLease::Status::Cancelled)
          ensure
            lease.close
          end
          lease.close
          handles.each do |handle|
            result = WindowsConsoleProbe::Native.GetHandleInformation(handle, out _)
            error = LibC.GetLastError
            result.should eq(0)
            error.should eq(6_u32)
          end
          WindowsConsoleProbe.check LibC.GetConsoleMode(input, out _), "GetConsoleMode(borrowed input)"
        end
        WindowsConsoleProbe.check WindowsConsole.GetNumberOfConsoleInputEvents(input, out after),
          "GetNumberOfConsoleInputEvents"
        after.should eq(before)
      end
    end

    it "rearms the production worker without consuming its readiness signal" do
      WindowsConsoleProbe.with_handle(WindowsConsoleProbe.event) do |input|
        WindowsConsoleProbe.check WindowsConsoleProbe::Native.SetEvent(input), "SetEvent"
        lease = Termisu::System::Console::ReadinessLease.new(input.address)
        begin
          lease.wait(monotonic_now + 1.second).should eq(Termisu::System::Console::ReadinessLease::Status::Ready)
          lease.rearm
          lease.wait(monotonic_now + 1.second).should eq(Termisu::System::Console::ReadinessLease::Status::Ready)
          handles = [input]
          WindowsConsoleProbe::Native.WaitForMultipleObjects(1_u32, handles, 0, 0_u32).should eq(LibC::WAIT_OBJECT_0)
        ensure
          lease.close
        end
      end
    end

    it "cancels a pending unread wake without requiring the source to drain it" do
      WindowsConsoleProbe.with_handle(WindowsConsoleProbe.event) do |input|
        WindowsConsoleProbe.check WindowsConsoleProbe::Native.SetEvent(input), "SetEvent"
        lease = Termisu::System::Console::ReadinessLease.new(input.address)
        begin
          deadline = monotonic_now + 1.second
          until lease.@wake_pending.get
            fail "native worker did not publish readiness" if monotonic_now >= deadline
            sleep 1.millisecond
          end
          lease.cancel
        ensure
          lease.close
        end
      end
    end

    it "reports the original native duplication failure during construction" do
      expect_raises(IO::Error, /DuplicateHandle/) do
        Termisu::System::Console::ReadinessLease.new(0_u64)
      end
    end

    it "preserves worker failures through notification failure, EOF and cleanup" do
      {% for type in ["WindowsConsoleProbe::FailedWaitLease", "WindowsConsoleProbe::FailedNotificationLease"] %}
        WindowsConsoleProbe.with_handle(WindowsConsoleProbe.event) do |input|
          WindowsConsoleProbe.check WindowsConsoleProbe::Native.SetEvent(input), "SetEvent"
          lease = {{type.id}}.new(input.address)
          begin
            lease.wait(monotonic_now + 1.second).should eq(Termisu::System::Console::ReadinessLease::Status::Error)
            lease.worker_error.should be(lease.failure)
          ensure
            error = expect_raises(IO::Error, /injected readiness/) { lease.close }
            error.should be(lease.failure)
          end
          lease.close
        end
      {% end %}
    end

    it "retains live wait resources when cancellation or joining fails" do
      [WindowsConsoleProbe::FailedCancellationLease, WindowsConsoleProbe::UnconfirmedJoinLease].each do |type|
        WindowsConsoleProbe.with_handle(WindowsConsoleProbe.event) do |input|
          lease = type.new(input.address)
          handles = [lease.@input, lease.@cancel, lease.@rearm,
                     LibC::HANDLE.new(lease.@reader.not_nil!.fd)]
          begin
            expect_raises(IO::Error, /injected/) { lease.close }
            handles.each do |handle|
              WindowsConsoleProbe.check WindowsConsoleProbe::Native.GetHandleInformation(handle, out _),
                "GetHandleInformation(retained wait resource)"
            end
          ensure
            lease.close
          end
          handles.each do |handle|
            result = WindowsConsoleProbe::Native.GetHandleInformation(handle, out _)
            error = LibC.GetLastError
            result.should eq(0)
            error.should eq(6_u32)
          end
        end
      end
    end

    it "delivers native VT arrows, modifiers, Unicode and NUL through the owned decoder" do
      WindowsConsoleProbe.with_console do |input, output|
        WindowsConsoleProbe.check WindowsConsole.GetNumberOfConsoleInputEvents(input, out before),
          "GetNumberOfConsoleInputEvents"
        before.should eq(0_u32)
        WindowsConsoleProbe.with_modes(input, output) do
          disabled = LibC::ENABLE_LINE_INPUT | LibC::ENABLE_ECHO_INPUT | LibC::ENABLE_PROCESSED_INPUT
          mode = WindowsConsoleProbe.mode(input) | LibC::ENABLE_VIRTUAL_TERMINAL_INPUT.to_u32 |
                 WindowsConsole::ENABLE_EXTENDED_FLAGS
          mode &= ~(disabled.to_u32 | WindowsConsole::ENABLE_QUICK_EDIT_MODE)
          WindowsConsoleProbe.check LibC.SetConsoleMode(input, mode), "SetConsoleMode(VT input)"
          WindowsConsoleProbe.check LibC.SetConsoleMode(output, WindowsConsoleProbe.mode(output) | 0x0005_u32),
            "SetConsoleMode(VT output)"
          records = [WindowsConsoleProbe.key(0x61, 0x41),
                     WindowsConsoleProbe.key(0, 0x26, state: 0x0100_u32),
                     WindowsConsoleProbe.key(0, 0x25, state: 0x0108_u32),
                     WindowsConsoleProbe.key(0x03BB, 0xE7),
                     WindowsConsoleProbe.key(0xD83D, 0xE7),
                     WindowsConsoleProbe.key(0xDE00, 0xE7),
                     WindowsConsoleProbe.key(0, 0x20, state: 0x0008_u32)]
          WindowsConsoleProbe.check WindowsConsole.WriteConsoleInputW(input, records, records.size.to_u32, out written),
            "WriteConsoleInputW(protocol fixture)"
          written.should eq(records.size)
          peek = Slice(WindowsConsole::InputRecord).new(32) { WindowsConsole::InputRecord.new }
          count = Termisu::System::Console.read_records(input, peek, remove: false)
          nul_records = peek[0, count].select do |record|
            record.event_type == WindowsConsole::KEY_EVENT && record.key_event.unicode_char == 0
          end.map { |record| {record.key_event.virtual_key_code, record.key_event.control_key_state} }
          decoder = Termisu::System::Console::Input.new(input.address)
          byte = Bytes.new(1)
          text = IO::Memory.new
          128.times do
            count = decoder.read(byte)
            break if count == 0
            text.write(byte[0, count])
          end
          expected = ["a\e[A\e[1;5Dλ😀\0", "a\eOA\e[1;5Dλ😀\0"]
          unless expected.includes?(text.to_s)
            STDERR.puts "NUL record keys/states=#{nul_records.inspect}; layout mapping=#{Termisu::System::Console::Keyboard.VkKeyScanW(0_u16)}"
          end
          expected.should contain(text.to_s)
          WindowsConsoleProbe.check WindowsConsole.GetNumberOfConsoleInputEvents(input, out after),
            "GetNumberOfConsoleInputEvents"
          after.should eq(0_u32)
        end
      end
    end

    it "preserves layout-mapped NUL records without emitting modifier-only keys" do
      WindowsConsoleProbe.with_console do |input, _output|
        mapping = Termisu::System::Console::Keyboard.VkKeyScanW(0_u16)
        state = 0_u32
        state |= 0x0010_u32 if (mapping & 0x0100) != 0
        state |= 0x0008_u32 if (mapping & 0x0200) != 0
        state |= 0x0002_u32 if (mapping & 0x0400) != 0
        decoder = WindowsConsoleProbe::BufferedInput.new(input.address)
        decoder.seed([WindowsConsoleProbe.key(0, 0x10, state: 0x0010_u32),
                      WindowsConsoleProbe.key(0, (mapping & 0xFF).to_u16, state: state),
                      WindowsConsoleProbe.key(0x78)])
        buffer = Bytes.new(8)
        count = decoder.read(buffer)
        String.new(buffer[0, count]).should eq("\0x")
      end
    end

    it "keeps split surrogate state per decoder and resets only library buffers" do
      WindowsConsoleProbe.with_console do |input, _output|
        first = WindowsConsoleProbe::BufferedInput.new(input.address)
        second = WindowsConsoleProbe::BufferedInput.new(input.address)
        buffer = Bytes.new(8)
        first.seed([WindowsConsoleProbe.key(0xD83D)])
        first.read(buffer).should eq(0)
        second.seed([WindowsConsoleProbe.key(0xDE00)])
        count = second.read(buffer)
        String.new(buffer[0, count]).should eq("\uFFFD")
        first.seed([WindowsConsoleProbe.key(0xDE00)])
        count = first.read(buffer)
        String.new(buffer[0, count]).should eq("😀")
        first.seed([WindowsConsoleProbe.key(0xD83D)])
        first.read(buffer).should eq(0)
        first.clear
        first.seed([WindowsConsoleProbe.key(0xDE00)])
        count = first.read(buffer)
        String.new(buffer[0, count]).should eq("\uFFFD")
      end
    end

    it "retains a large repeat count without expanding a pending allocation" do
      WindowsConsoleProbe.with_console do |input, _output|
        decoder = WindowsConsoleProbe::BufferedInput.new(input.address)
        decoder.seed([WindowsConsoleProbe.key(0x78, repeats: UInt16::MAX)])
        byte = Bytes.new(1)
        decoder.read(byte).should eq(1)
        byte[0].should eq(0x78_u8)
        decoder.@repeats.should eq(UInt16::MAX.to_i32 - 1)
        decoder.@pending.bytesize.should eq(1)
        decoder.buffered?.should be_true
        decoder.clear
        decoder.buffered?.should be_false
      end
    end

    it "writes split UTF-8 through a borrowed inactive wide-console handle" do
      WindowsConsoleProbe.with_screen_buffer do |handle|
        output = Termisu::System::Console::Output.new(handle.address)
        text = "λé".to_slice
        output.write(text[0, 1])
        output.flush
        WindowsConsoleProbe.check WindowsConsole.GetConsoleScreenBufferInfo(handle, out before), "GetConsoleScreenBufferInfo"
        before.cursor_position.x.should eq(0)
        output.write(text[1, text.size - 1])
        output.finish
        WindowsConsoleProbe.screen_text(handle, 2).should eq([0x03BB_u16, 0x00E9_u16])
        WindowsConsoleProbe.mode(handle).should be_a(UInt32)
      end
    end

    it "bounds wide-console output buffering across large writes" do
      WindowsConsoleProbe.with_screen_buffer do |handle|
        output = Termisu::System::Console::Output.new(handle.address)
        output.write(("x" * 20_000).to_slice)
        output.@buffer.size.should be < Termisu::System::Console::Output::CAPACITY
        output.finish
        output.@buffer.empty?.should be_true
        WindowsConsoleProbe.screen_text(handle, 5).should eq(Array(UInt16).new(5, 0x78_u16))
      end
    end

    it "rejects invalid or unfinished UTF-8 without closing its borrowed handle" do
      WindowsConsoleProbe.with_screen_buffer do |handle|
        output = Termisu::System::Console::Output.new(handle.address)
        output.write(Bytes[0xFF])
        expect_raises(IO::Error, "Invalid UTF-8 console output") { output.flush }
        output.write("a".to_slice)
        output.finish
        WindowsConsoleProbe.screen_text(handle, 1).should eq([0x61_u16])
        output.write(Bytes[0xCE])
        expect_raises(IO::Error, "Incomplete UTF-8 console output") { output.finish }
        WindowsConsoleProbe.mode(handle).should be_a(UInt32)
      end
    end

    it "owns native-width noninheritable console handles instead of standard streams" do
      WindowsConsoleProbe.with_console do |input, output|
        original_input = WindowsConsoleProbe.mode(input)
        original_output = WindowsConsoleProbe.mode(output)
        tty = Termisu::TTY.new
        input_handle, output_handle = LibC::HANDLE.new(tty.infd), LibC::HANDLE.new(tty.outfd)
        begin
          tty.infd.should_not eq(STDIN.fd)
          tty.outfd.should_not eq(STDOUT.fd)
          [input_handle, output_handle].each do |handle|
            WindowsConsoleProbe.check WindowsConsoleProbe::Native.GetHandleInformation(handle, out flags), "GetHandleInformation(TTY)"
            (flags & WindowsConsoleProbe::Native::HANDLE_FLAG_INHERIT).should eq(0_u32)
            WindowsConsoleProbe.mode(handle).should be_a(UInt32)
          end
        ensure
          tty.close
          tty.close
        end
        WindowsConsoleProbe::Native.GetHandleInformation(input_handle, out _).should eq(0)
        WindowsConsoleProbe::Native.GetHandleInformation(output_handle, out _).should eq(0)
        WindowsConsoleProbe.mode(input).should eq(original_input)
        WindowsConsoleProbe.mode(output).should eq(original_output)
        STDIN.closed?.should be_false
        STDOUT.closed?.should be_false
      end
    end

    it "restores shared console modes and rejects unsupported echo transactionally" do
      WindowsConsoleProbe.with_console do |input, output|
        WindowsConsoleProbe.with_modes(input, output) do
          original_input = WindowsConsoleProbe.mode(input)
          original_output = WindowsConsoleProbe.mode(output)
          backend = Termisu::Terminal::Backend.new
          begin
            modes = [Termisu::Terminal::Mode.raw, Termisu::Terminal::Mode.semi_raw,
                     Termisu::Terminal::Mode.cooked, Termisu::Terminal::Mode.password]
            modes.each do |mode|
              backend.set_mode(mode)
              bits = WindowsConsoleProbe.mode(input)
              ((bits & 0x0002) != 0).should eq(mode.canonical?)
              ((bits & 0x0004) != 0).should eq(mode.echo?)
              ((bits & 0x0001) != 0).should eq(mode.signals?)
              unless mode.canonical?
                (bits & 0x0200).should_not eq(0_u32)
                (bits & 0x0040).should eq(0_u32)
                (WindowsConsoleProbe.mode(output) & 0x0005).should eq(0x0005_u32)
              end
            end
            before = {WindowsConsoleProbe.mode(input), WindowsConsoleProbe.mode(output)}
            expect_raises(NotImplementedError, "Windows console echo requires canonical input") do
              backend.set_mode(Termisu::Terminal::Mode.cbreak)
            end
            {WindowsConsoleProbe.mode(input), WindowsConsoleProbe.mode(output)}.should eq(before)
            backend.current_mode.should eq(Termisu::Terminal::Mode.password)
          ensure
            backend.close
          end
          WindowsConsoleProbe.mode(input).should eq(original_input)
          WindowsConsoleProbe.mode(output).should eq(original_output)
        end
      end
    end

    it "rolls back input mode when setting output mode fails" do
      WindowsConsoleProbe.with_console do |input, output|
        WindowsConsoleProbe.with_modes(input, output) do
          before = {WindowsConsoleProbe.mode(input), WindowsConsoleProbe.mode(output)}
          modes = WindowsConsoleProbe::FailedOutputMode.new(input.address, output.address)
          error = expect_raises(IO::Error, "injected console output mode failure") do
            modes.set_mode(Termisu::Terminal::Mode.raw)
          end
          error.should be(modes.failure)
          modes.current_mode.should be_nil
          {WindowsConsoleProbe.mode(input), WindowsConsoleProbe.mode(output)}.should eq(before)
          modes.restore
        end
      end
    end

    it "restarts the shared input source without losing buffered native input" do
      WindowsConsoleProbe.with_console do |input, output|
        WindowsConsoleProbe.with_modes(input, output) do
          backend = Termisu::Terminal::Backend.new
          backend.enable_raw_mode
          reader = Termisu::Reader.new(backend.infd)
          parser = Termisu::Input::Parser.new(reader)
          source = Termisu::Event::Source::Input.new(reader, parser)
          events = Channel(Termisu::Event::Any).new
          delivered = 0
          begin
            source.start(events)
            WindowsConsoleProbe.write_keys(input, 0x71_u16, count: 384)
            WindowsConsoleProbe.key_event(WindowsConsoleProbe.receive(events)).char.should eq('q')
            delivered += 1
            source.stop
            source.start(events)
            383.times do
              WindowsConsoleProbe.key_event(WindowsConsoleProbe.receive(events)).char.should eq('q')
              delivered += 1
            end
            source.stop
            source.running?.should be_false
            source.stop_required?.should be_false
            reader.eof?.should be_false
          rescue error
            STDERR.puts "Native input restart delivered #{delivered}/384 keys"
            raise error
          ensure
            source.stop
            reader.close
            backend.close
          end
        end
      end
    end

    it "runs the facade, raw-reader handoff and cooked scopes over owned console I/O" do
      WindowsConsoleProbe.with_console do |input, output|
        WindowsConsoleProbe.with_modes(input, output) do
          original = {WindowsConsoleProbe.mode(input), WindowsConsoleProbe.mode(output)}
          term = Termisu.new
          stage = "initial key"
          begin
            term.set_cell(0, 0, 'λ')
            term.render
            WindowsConsoleProbe.with_handle(WindowsConsoleProbe.open_console("CONOUT$")) do |active|
              WindowsConsoleProbe.screen_text(active, 1).should eq([0x03BB_u16])
            end
            WindowsConsoleProbe.write_keys(input, 0x71_u16)
            WindowsConsoleProbe.key_event(term.poll_event(2.seconds)).char.should eq('q')
            stage = "raw wait"
            term.with_raw_input do
              WindowsConsoleProbe.write_keys(input, 0x72_u16, count: 2)
              term.wait_for_input(250).should be_true
              term.read_byte.should eq(0x72_u8)
            end
            stage = "raw handback"
            WindowsConsoleProbe.key_event(term.poll_event(2.seconds)).char.should eq('r')
            stage = "cooked scope"
            term.with_mode(Termisu::Terminal::Mode.cooked) do
              (WindowsConsoleProbe.mode(input) & 0x0002).should_not eq(0_u32)
              WindowsConsoleProbe.write_keys(input, 0x63_u16)
            end
            stage = "cooked handback"
            change = term.poll_event(2.seconds)
            change.should be_a(Termisu::Event::ModeChange)
            change.as(Termisu::Event::ModeChange).mode.should eq(Termisu::Terminal::Mode.cooked)
            change.as(Termisu::Event::ModeChange).previous_mode.should eq(Termisu::Terminal::Mode.raw)
            change = term.poll_event(2.seconds)
            change.should be_a(Termisu::Event::ModeChange)
            change.as(Termisu::Event::ModeChange).mode.should eq(Termisu::Terminal::Mode.raw)
            change.as(Termisu::Event::ModeChange).previous_mode.should eq(Termisu::Terminal::Mode.cooked)
            WindowsConsoleProbe.key_event(term.poll_event(2.seconds)).char.should eq('c')
          rescue error
            STDERR.puts "Native facade input failed at #{stage}"
            raise error
          ensure
            term.close
          end
          {WindowsConsoleProbe.mode(input), WindowsConsoleProbe.mode(output)}.should eq(original)
          STDIN.closed?.should be_false
          STDOUT.closed?.should be_false
        end
      end
    end

    it "keeps software timer expirations and the original SystemTimer lifecycle" do
      poller = Termisu::Event::Poller.create
      begin
        handle = poller.add_timer(3.milliseconds)
        sleep 20.milliseconds
        event = poller.wait(Time::Span.zero)
        event.should_not be_nil
        event.not_nil!.timer?.should be_true
        event.not_nil!.timer_expirations.should be >= 2_u64
        poller.remove_timer(handle)
        expect_raises(NotImplementedError, "Generic descriptor polling is not supported on Windows") do
          poller.register_fd(0, Termisu::Event::Poller::FDEvents::Read)
        end
      ensure
        poller.close
      end
      timer = Termisu::Event::Source::SystemTimer.new(4.milliseconds)
      timer.class.to_s.should eq("Termisu::Event::Source::SystemTimer")
      events = Channel(Termisu::Event::Any).new
      begin
        2.times do
          timer.start(events)
          WindowsConsoleProbe.receive(events).should be_a(Termisu::Event::Tick)
          timer.stop
          timer.running?.should be_false
        end
      ensure
        timer.stop
      end
    end

    it "defers bottom-right wrapping instead of scrolling the shared render grid" do
      WindowsConsoleProbe.with_screen_buffer do |handle|
        bits = WindowsConsoleProbe.mode(handle)
        WindowsConsoleProbe.check LibC.SetConsoleMode(handle, bits | 0x000D_u32), "SetConsoleMode(delayed wrap)"
        WindowsConsoleProbe.check WindowsConsole.GetConsoleScreenBufferInfo(handle, out info), "GetConsoleScreenBufferInfo"
        width = info.window.right.to_i32 - info.window.left.to_i32 + 1
        height = info.window.bottom.to_i32 - info.window.top.to_i32 + 1
        output = Termisu::System::Console::Output.new(handle.address)
        output.write("\e[HA\e[#{height};#{width}HZ\e[H".to_slice)
        output.finish
        WindowsConsoleProbe.screen_text(handle, 1).should eq([0x41_u16])
      end
    end

    it "restores console modes despite output failure in every cleanup scope" do
      WindowsConsoleProbe.with_console do |input, output|
        WindowsConsoleProbe.with_modes(input, output) do
          ["disable", "with_raw", "with_mode", "close"].each do |operation|
            backend = Termisu::Terminal::Backend.new
            begin
              backend.set_mode(Termisu::Terminal::Mode.cooked) if operation == "with_mode"
              before = {WindowsConsoleProbe.mode(input), WindowsConsoleProbe.mode(output)}
              expect_raises(IO::Error, "Invalid UTF-8 console output") do
                case operation
                when "with_raw"
                  backend.with_raw_mode { backend.write(Bytes[0xFF]) }
                when "with_mode"
                  backend.with_mode(Termisu::Terminal::Mode.raw) { backend.write(Bytes[0xFF]) }
                else
                  backend.enable_raw_mode
                  backend.write(Bytes[0xFF])
                  operation == "close" ? backend.close : backend.disable_raw_mode
                end
              end
              {WindowsConsoleProbe.mode(input), WindowsConsoleProbe.mode(output)}.should eq(before)
              backend.raw_mode?.should be_false
            ensure
              backend.close
            end
          end
        end
      end
    end

    it "retains an unconfirmed native lease before allowing source replacement" do
      WindowsConsoleProbe.with_console do |input, _output|
        reader = Termisu::Reader.new(input.address)
        source = WindowsConsoleProbe::RetainedInputSource.new(reader, Termisu::Input::Parser.new(reader))
        lease = WindowsConsoleProbe::UnconfirmedJoinLease.new(input.address)
        events = Channel(Termisu::Event::Any).new(1)
        source.seed_lease(lease)
        begin
          expect_raises(IO::Error, "injected unconfirmed join") { source.start(events) }
          lease.closed?.should be_false
          source.stop_required?.should be_true
          source.@lease.should be(lease)
          source.running?.should be_false
          source.start(events)
          lease.closed?.should be_true
          source.running?.should be_true
          source.stop
          source.stop_required?.should be_false
        ensure
          source.stop
          reader.close
        end
      end
    end
  end
{% end %}
