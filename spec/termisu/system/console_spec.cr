require "spec"

{% if flag?(:win32) %}
  # Run standalone in an attached console: crystal spec spec/termisu/system/console_spec.cr
  # Deliberately avoid the facade until its POSIX input lease has a Windows path.
  class Termisu
  end

  require "../../../src/termisu/system/console"
  require "../../../src/termisu/system/console/readiness_lease"
  require "../../../src/termisu/time_compat"

  alias WindowsConsole = Termisu::System::Console::C

  module WindowsConsoleProbe
    extend self

    @[Link("kernel32")]
    lib Native
      HANDLE_FLAG_INHERIT     = 0x0001_u32
      ENABLE_PROCESSED_OUTPUT = 0x0001_u32

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
      @fail_once = true

      private def signal_cancellation : Nil
        if @fail_once
          @fail_once = false
          raise IO::Error.new("injected cancellation failure")
        end
        super
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
      sizeof(WindowsConsole::InputRecord).should eq(20)
      offsetof(WindowsConsole::InputRecord, @key_event).should eq(4)
      sizeof(WindowsConsole::ScreenBufferInfo).should eq(22)
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

  end
{% end %}
