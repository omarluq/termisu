require "../console"
require "../../time_compat"

{% if flag?(:win32) %}
  # A run owns its duplicate, cancellation/rearm events and cooperative wake pipe.
  # The native worker only observes readiness; it never consumes console input.
  class Termisu::System::Console::ReadinessLease
    {% if compare_versions(Crystal::VERSION, "1.21.0") < 0 || compare_versions(Crystal::VERSION, "1.22.0") >= 0 %}
      {% raise "Termisu Windows readiness supports Crystal >= 1.21.0, < 1.22.0" %}
    {% end %}

    enum Status : UInt8
      Ready     = 1
      Hangup    = 2
      Error     = 3
      Cancelled = 4
    end

    @input : LibC::HANDLE
    @cancel : LibC::HANDLE
    @rearm : LibC::HANDLE
    @writer : LibC::HANDLE
    @reader : IO::FileDescriptor?
    @thread : Thread?
    @closed = Atomic(Bool).new(false)
    @cancelled = Atomic(Bool).new(false)
    @wake_pending = Atomic(Bool).new(false)
    @worker_failed = Atomic(Bool).new(false)
    @worker_error : Exception?

    def initialize(fd : IO::FileDescriptor::Handle)
      @input = @cancel = @rearm = @writer = Pointer(Void).null
      begin
        @input = duplicate(LibC::HANDLE.new(fd))
        @cancel = event(manual: true)
        @rearm = event(manual: false)
        reader, writer = IO.pipe(read_blocking: false, write_blocking: true)
        @reader = reader
        begin
          @writer = duplicate(LibC::HANDLE.new(writer.fd))
        ensure
          writer.close
        end
        thread = Thread.new { worker_loop }
        if thread.to_unsafe.null?
          raise IO::Error.new("Native input readiness thread could not be started")
        end
        @thread = thread
      rescue error
        close_resources
        raise error
      end
    end

    def wait(deadline : MonotonicTime?) : Status?
      reader = @reader || raise IO::Error.new("Input readiness lease is closed")
      if deadline
        remaining = deadline - monotonic_now
        return if remaining <= Time::Span.zero
        reader.read_timeout = remaining
      else
        reader.read_timeout = nil
      end
      if byte = reader.read_byte
        @wake_pending.set(false)
        Status.from_value(byte)
      elsif @worker_failed.get
        Status::Error
      elsif @cancelled.get
        Status::Cancelled
      else
        raise IO::Error.new("Input readiness worker closed its wake pipe unexpectedly")
      end
    rescue IO::TimeoutError
      nil
    end

    def worker_failed? : Bool
      @worker_failed.get
    end

    def worker_error : Exception
      if @worker_failed.get && (error = @worker_error)
        return error
      end
      raise IO::Error.new("Input readiness worker failed without a recorded error")
    end

    def rearm : Nil
      return if @cancelled.get
      if C.SetEvent(@rearm) == 0
        raise IO::Error.from_winerror("SetEvent(input rearm)")
      end
    end

    def cancel : Nil
      return if @cancelled.get
      signal_cancellation
      @cancelled.set(true)
    end

    private def signal_cancellation : Nil
      if C.SetEvent(@cancel) == 0
        raise IO::Error.from_winerror("SetEvent(input cancellation)")
      end
    end

    def close : Nil
      return unless @closed.compare_and_set(false, true)[1]
      begin
        cancel
        join_worker
      rescue error
        # A failed native join does not establish termination; retain all wait resources.
        @closed.set(false)
        raise error
      end
      cleanup_error = close_resources
      raise worker_error if @worker_failed.get
      raise cleanup_error if cleanup_error
    end

    private def join_worker : Nil
      @thread.try(&.join)
    end

    private def worker_loop : Nil
      input_wait = [@cancel, @input]
      rearm_wait = [@cancel, @rearm]
      loop do
        if wait_handles(input_wait) == 0
          publish(Status::Cancelled)
          break
        end
        publish(Status::Ready)
        if wait_handles(rearm_wait) == 0
          publish(Status::Cancelled)
          break
        end
      end
    rescue error
      record_failure(error)
      publish(Status::Error) rescue nil
    ensure
      # Closing the sole writer also wakes the cooperative reader if publication failed.
      if LibC.CloseHandle(@writer) == 0
        record_failure(IO::Error.from_winerror("CloseHandle(input wake writer)"))
      end
    end

    private def record_failure(error : Exception) : Nil
      @worker_error ||= error
      @worker_failed.set(true)
    end

    private def wait_handles(handles : Array(LibC::HANDLE)) : UInt32
      result = C.WaitForMultipleObjects(handles.size.to_u32, handles, 0, UInt32::MAX)
      if result == LibC::WAIT_FAILED
        raise IO::Error.from_winerror("WaitForMultipleObjects(input readiness)")
      end
      unless result < handles.size
        raise IO::Error.new("Unexpected input readiness wait result: #{result}")
      end
      result
    end

    private def publish(status : Status) : Nil
      # There is at most one unread wake byte, so a synchronous write cannot fill the pipe.
      return unless @wake_pending.compare_and_set(false, true)[1]
      byte = status.value
      if LibC.WriteFile(@writer, pointerof(byte), 1_u32, out written, nil) == 0
        raise IO::Error.from_winerror("WriteFile(input wake)")
      end
      raise IO::Error.new("Input wake write was incomplete") unless written == 1
    end

    private def duplicate(handle : LibC::HANDLE) : LibC::HANDLE
      process = LibC.GetCurrentProcess
      if LibC.DuplicateHandle(process, handle, process, out copy, 0_u32, 0, LibC::DUPLICATE_SAME_ACCESS) == 0
        raise IO::Error.from_winerror("DuplicateHandle(input readiness)")
      end
      copy
    end

    private def event(*, manual : Bool) : LibC::HANDLE
      handle = C.CreateEventW(nil, manual ? 1 : 0, 0, nil)
      raise IO::Error.from_winerror("CreateEventW(input readiness)") if handle.null?
      handle
    end

    private def close_resources : Exception?
      error = nil.as(Exception?)
      begin
        @reader.try(&.close)
      rescue ex
        error = ex
      end
      @reader = nil
      # Once started, the worker owns and closes the writer, before join returns.
      handles = @thread ? [@input, @cancel, @rearm] : [@input, @cancel, @rearm, @writer]
      handles.each do |handle|
        next if handle.null?
        if LibC.CloseHandle(handle) == 0
          close_error = IO::Error.from_winerror("CloseHandle(input readiness)")
          error ||= close_error
        end
      end
      @input = @cancel = @rearm = @writer = Pointer(Void).null
      error
    end
  end
{% end %}
