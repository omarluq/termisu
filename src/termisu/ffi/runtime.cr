{% if flag?(:linux) %}
  # bdwgc's stop-the-world signal setters. Crystal's stdlib `LibGC` (the GC
  # runtime every Crystal binary already links) binds only the getters, so
  # reopen it to add them — no new library, no extra link flags. bdwgc
  # requires the setters to be called before `GC.init` installs the
  # suspend/restart handlers.
  #
  # Linux-only: on macOS bdwgc suspends threads via Mach APIs (no signals),
  # and other platforms keep bdwgc's defaults until proven problematic.
  lib LibGC
    fun set_suspend_signal = GC_set_suspend_signal(sig : Int) : Void
    fun set_thr_restart_signal = GC_set_thr_restart_signal(sig : Int) : Void
  end

  lib LibC
    fun __libc_current_sigrtmax : Int
  end
{% end %}

module Termisu::FFI::Runtime
  @@bootstrapped = Atomic(Bool).new(false)
  @@bootstrapping = Atomic(Bool).new(false)

  def self.mark_bootstrapped! : Nil
    @@bootstrapped.set(true)
  end

  def self.ensure_initialized : Nil
    loop do
      return if @@bootstrapped.get

      unless @@bootstrapping.compare_and_set(false, true)
        # Runtime may not be initialized yet; use OS-thread yield instead of fiber scheduling.
        LibC.sched_yield
        next
      end

      begin
        return if @@bootstrapped.get

        {% if flag?(:linux) %}
          # bdwgc defaults its stop-the-world suspend/restart signals to
          # SIGPWR/SIGXCPU on Linux. Host runtimes embedding this shared
          # library may claim SIGPWR too (JavaScriptCore, Bun's JS engine,
          # uses it to suspend threads for GC stack scans); `GC.init` would
          # overwrite the host's process-global SIGPWR handler, so the host's
          # next suspend signal runs bdwgc's handler on a thread bdwgc never
          # registered and crashes (NULL deref). Move bdwgc to the top of the
          # real-time signal range, which no host runtime uses. Must run
          # before `GC.init`.
          rtmax = LibC.__libc_current_sigrtmax
          LibGC.set_suspend_signal(rtmax)
          LibGC.set_thr_restart_signal(rtmax - 1)
        {% end %}

        GC.init
        Crystal.init_runtime

        argv = StaticArray(UInt8*, 1).new("termisu-ffi".to_unsafe.as(UInt8*))
        Crystal.main_user_code(1, argv.to_unsafe)
        @@bootstrapped.set(true)
        return
      rescue ex
        @@bootstrapped.set(false)
        raise ex
      ensure
        @@bootstrapping.set(false)
      end
    end
  end
end

# When running as a regular Crystal program, `__crystal_main` executes this
# and runtime is already initialized. In shared-library mode this line does not
# execute before FFI calls, so `ensure_initialized` performs bootstrap.
Termisu::FFI::Runtime.mark_bootstrapped!
