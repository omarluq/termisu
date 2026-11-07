require "json"

{% unless flag?(:win32) %}
  {% raise "This diagnostic requires native Windows" %}
{% end %}

@[Link("kernel32")]
lib SDKThreadNative
  fun GetHandleInformation(handle : LibC::HANDLE, flags : LibC::DWORD*) : LibC::BOOL
  fun GetProcessHandleCount(process : LibC::HANDLE, count : LibC::DWORD*) : LibC::BOOL
end

module SDKThreadCleanup
  SAMPLES = 32

  def self.handle_open?(handle : LibC::HANDLE) : Bool
    return true unless SDKThreadNative.GetHandleInformation(handle, out flags) == 0
    error = LibC.GetLastError
    raise "GetHandleInformation failed: #{error}" unless error == 6 # ERROR_INVALID_HANDLE
    false
  end

  def self.handle_count : UInt32
    if SDKThreadNative.GetProcessHandleCount(LibC.GetCurrentProcess, out count) == 0
      raise RuntimeError.from_winerror("GetProcessHandleCount")
    end
    count
  end

  def self.wait_exited(handle : LibC::HANDLE) : Nil
    unless LibC.WaitForSingleObject(handle, 2000) == LibC::WAIT_OBJECT_0
      raise "Diagnostic worker did not terminate within two seconds"
    end
  end

  def self.sample(join_first : Bool)
    release = Atomic(Bool).new(false)
    join_won_gate = Atomic(Bool).new(false)
    worker = Thread.new do |thread|
      deadline = Time.instant + 2.seconds
      until release.get || (join_first && thread.@detached.get)
        raise "Diagnostic worker release timed out" if Time.instant >= deadline
        Crystal::System::Thread.sleep(1.millisecond)
      end
      join_won_gate.set(thread.@detached.get)
    end

    owned_thread = Pointer(Void).null
    semaphore : LibC::HANDLE? = nil
    semaphore_open : Bool? = nil
    failure : Exception? = nil
    begin
      original_thread = worker.to_unsafe
      raise "SDK thread HANDLE was not valid before join" unless handle_open?(original_thread)
      process = LibC.GetCurrentProcess
      # The SDK closes its original HANDLE; our duplicate proves actual OS termination.
      if LibC.DuplicateHandle(process, original_thread, process, pointerof(owned_thread), 0, 0, 2) == 0
        raise RuntimeError.from_winerror("DuplicateHandle")
      end
      {% if compare_versions(Crystal::VERSION, "1.22.0") >= 0 %}
        semaphore = worker.@semaphore
        raise "SDK semaphore was not valid before join" unless handle_open?(semaphore)
      {% end %}

      unless join_first
        release.set(true)
        wait_exited(owned_thread)
      end
      worker.join
      wait_exited(owned_thread)
      raise "SDK detach gate ordering was not forced" unless join_won_gate.get == join_first
      raise "SDK thread HANDLE remained open after join" if handle_open?(original_thread)
      semaphore_open = handle_open?(semaphore) if semaphore
    rescue error
      failure = error
    ensure
      unless owned_thread.null?
        if LibC.CloseHandle(owned_thread) == 0
          failure ||= RuntimeError.from_winerror("CloseHandle diagnostic duplicate")
        end
      end
    end
    raise failure if failure
    {join_won_gate: join_won_gate.get, semaphore: semaphore, semaphore_open: semaphore_open}
  end

  def self.phase(join_first : Bool)
    before = handle_count
    samples = Array.new(SAMPLES) { sample(join_first) }
    after_join = handle_count
    GC.collect
    after_gc = handle_count
    still_open = samples.count do |result|
      if semaphore = result[:semaphore]
        handle_open?(semaphore)
      else
        false
      end
    end
    {
      mode:                       join_first ? "join-first" : "exit-first",
      samples:                    SAMPLES,
      forced_order_samples:       samples.count { |result| result[:join_won_gate] == join_first },
      terminated_threads:         SAMPLES,
      closed_thread_handles:      SAMPLES,
      inspected_semaphores:       samples.count { |result| !result[:semaphore].nil? },
      open_semaphores_after_join: samples.count { |result| result[:semaphore_open] == true },
      open_semaphores_after_gc:   still_open,
      process_handles_before:     before,
      process_handles_after_join: after_join,
      process_handles_after_gc:   after_gc,
    }
  end

  def self.run : Nil
    # Warm up both paths before measuring; report rather than hide the warmup leak.
    warmup = [sample(false), sample(true)].map { |result| result[:semaphore_open] }
    phases = [phase(false), phase(true)]
    puts({
      probe:                     "sdk-thread-cleanup",
      crystal:                   Crystal::VERSION,
      platform:                  "windows",
      pointer_bytes:             sizeof(Void*),
      warmup_open_semaphores:    warmup,
      phases:                    phases,
      joined_semaphore_retained: phases.last[:open_semaphores_after_join] > 0,
    }.to_json)
  end
end

SDKThreadCleanup.run
