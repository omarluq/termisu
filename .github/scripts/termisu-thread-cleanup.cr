require "json"
require "../../src/termisu"

{% unless flag?(:win32) %}
  {% raise "This diagnostic requires native Windows" %}
{% end %}

@[Link("kernel32")]
lib TermisuThreadNative
  fun GetHandleInformation(handle : LibC::HANDLE, flags : LibC::DWORD*) : LibC::BOOL
  fun GetProcessHandleCount(process : LibC::HANDLE, count : LibC::DWORD*) : LibC::BOOL
end

module TermisuThreadCleanup
  SAMPLES = 32

  def self.handle_open?(handle : LibC::HANDLE) : Bool
    return true unless TermisuThreadNative.GetHandleInformation(handle, out flags) == 0
    error = LibC.GetLastError
    raise "GetHandleInformation failed: #{error}" unless error == 6 # ERROR_INVALID_HANDLE
    false
  end

  def self.handle_count : UInt32
    if TermisuThreadNative.GetProcessHandleCount(LibC.GetCurrentProcess, out count) == 0
      raise RuntimeError.from_winerror("GetProcessHandleCount")
    end
    count
  end

  def self.sample(input : LibC::HANDLE)
    lease = Termisu::System::Console::ReadinessLease.new(input.address)
    owned_thread = Pointer(Void).null
    close_attempted = false
    failure : Exception? = nil
    semaphore : LibC::HANDLE? = nil
    semaphore_open : Bool? = nil
    begin
      worker = lease.@thread || raise "Production readiness worker was not started"
      reader = lease.@reader || raise "Production readiness reader was not opened"
      original_thread = worker.to_unsafe
      handles = [lease.@input, lease.@cancel, lease.@rearm, lease.@writer,
                 LibC::HANDLE.new(reader.fd)]
      raise "Production readiness handle was not open" unless handles.all? { |handle| handle_open?(handle) }
      process = LibC.GetCurrentProcess
      if LibC.DuplicateHandle(process, original_thread, process, pointerof(owned_thread), 0, 0, 2) == 0
        raise RuntimeError.from_winerror("DuplicateHandle")
      end
      {% if compare_versions(Crystal::VERSION, "1.22.0") >= 0 %}
        semaphore = worker.@semaphore
        raise "SDK semaphore was not open" unless handle_open?(semaphore)
      {% end %}
      close_attempted = true
      lease.close
      unless LibC.WaitForSingleObject(owned_thread, 2000) == LibC::WAIT_OBJECT_0
        raise "Production readiness worker did not terminate within two seconds"
      end
      raise "Production readiness lease did not close" unless lease.closed?
      raise "Production readiness handle remained open" if handles.any? { |handle| handle_open?(handle) }
      raise "SDK thread HANDLE remained open" if handle_open?(original_thread)
      semaphore_open = handle_open?(semaphore) if semaphore
    rescue error
      failure = error
    ensure
      # A failed SDK join is cached; never retry it to infer termination.
      unless close_attempted
        begin
          lease.close
        rescue error
          failure ||= error
        end
      end
      unless owned_thread.null?
        if LibC.CloseHandle(owned_thread) == 0
          failure ||= RuntimeError.from_winerror("CloseHandle diagnostic duplicate")
        end
      end
    end
    raise failure if failure
    {semaphore: semaphore, semaphore_open: semaphore_open}
  end

  def self.run : Nil
    # An idle native event exercises the real lease without consuming console input.
    input = Termisu::System::Console::C.CreateEventW(nil, 1, 0, nil)
    raise RuntimeError.from_winerror("CreateEventW") if input.null?
    failure : Exception? = nil
    begin
      warmup = Array.new(2) { sample(input)[:semaphore_open] }
      GC.collect
      before = handle_count
      samples = Array.new(SAMPLES) { sample(input) }
      after_close = handle_count
      GC.collect
      after_gc = handle_count
      open_after_gc = samples.count do |result|
        if semaphore = result[:semaphore]
          handle_open?(semaphore)
        else
          false
        end
      end
      puts({
        probe:                       "termisu-readiness-cleanup",
        crystal:                     Crystal::VERSION,
        platform:                    "windows",
        pointer_bytes:               sizeof(Void*),
        input_fixture:               "idle native event; no console input consumed",
        samples:                     SAMPLES,
        warmup_open_semaphores:      warmup,
        terminated_threads:          SAMPLES,
        closed_thread_handles:       SAMPLES,
        closed_owned_handles:        SAMPLES * 5,
        inspected_semaphores:        samples.count { |result| !result[:semaphore].nil? },
        open_semaphores_after_close: samples.count { |result| result[:semaphore_open] == true },
        open_semaphores_after_gc:    open_after_gc,
        process_handles_before:      before,
        process_handles_after_close: after_close,
        process_handles_after_gc:    after_gc,
      }.to_json)
    rescue error
      failure = error
    ensure
      if LibC.CloseHandle(input) == 0
        failure ||= RuntimeError.from_winerror("CloseHandle input fixture")
      end
    end
    raise failure if failure
  end
end

TermisuThreadCleanup.run
