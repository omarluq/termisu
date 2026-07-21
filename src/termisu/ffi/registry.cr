module Termisu::FFI::Registry
  # Maps opaque C handles to live contexts. Every guarded C ABI call resolves its handle
  # here, so this table is on the hot path of the entire FFI surface.
  #
  # The lock is a raw atomic spinlock rather than `Mutex`: the C ABI may be entered from
  # arbitrary host threads, and a contended `Mutex` parks the calling *fiber* through the
  # scheduler, which aborts the process when it happens off the main thread in default
  # (non-`execution_context`) builds. Critical sections here are a single Hash op, so
  # busy-waiting is safe on any thread. Heavy work (e.g. `Context#close`) must stay
  # outside `sync` — callers mutate the table under the lock and clean up after.
  @@lock = Atomic(Bool).new(false)
  @@contexts = {} of UInt64 => Termisu::FFI::Context
  @@next_handle = 1_u64

  def self.insert(context : Termisu::FFI::Context) : UInt64
    sync do
      handle = @@next_handle
      @@next_handle += 1_u64
      @@contexts[handle] = context
      handle
    end
  end

  def self.fetch(handle : UInt64) : Termisu::FFI::Context?
    sync { @@contexts[handle]? }
  end

  def self.delete(handle : UInt64) : Termisu::FFI::Context?
    sync { @@contexts.delete(handle) }
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
