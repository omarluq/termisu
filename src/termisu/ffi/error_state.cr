module Termisu::FFI::ErrorState
  # Per-thread last error message, in the errno style the C API expects: a caller runs an
  # operation and then reads the message back, without another thread's failure overwriting it.
  #
  # `Crystal::ThreadLocalValue` (removed in Crystal 1.21) is replaced with a minimal equivalent.
  # A plain `@[ThreadLocal]` class variable is not a safe substitute for a String: a value
  # reachable only from thread-local storage is invisible to the GC, and the annotation is
  # unavailable on emulated-TLS targets. Keying a Hash on the current thread keeps a strong
  # reference and works everywhere.
  #
  # The lock is a raw atomic spinlock rather than `Mutex`: the C ABI may be entered from
  # arbitrary host threads, and a contended `Mutex` parks the calling *fiber* through the
  # scheduler, which aborts the process when it happens off the main thread in default
  # (non-`execution_context`) builds. Critical sections here are a single Hash op, so
  # busy-waiting is safe on any thread.
  @@lock = Atomic(Bool).new(false)
  @@last_error = {} of Thread => String

  def self.current : String
    sync { @@last_error[Thread.current]? } || ""
  end

  def self.set(message : String) : Nil
    sync { @@last_error[Thread.current] = message }
  end

  def self.clear : Nil
    # Dropping the entry and storing "" are indistinguishable through `current`; dropping it
    # also releases the message.
    sync { @@last_error.delete(Thread.current) }
  end

  def self.format(ex : Exception) : String
    msg = ex.message
    msg ? "#{ex.class.name}: #{msg}" : ex.class.name
  end

  private def self.sync(&)
    until @@lock.compare_and_set(false, true, :acquire, :relaxed)[1]
    end
    begin
      yield
    ensure
      @@lock.set(false, :release)
    end
  end
end
