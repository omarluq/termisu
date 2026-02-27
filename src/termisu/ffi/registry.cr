module Termisu::FFI::Registry
  @@contexts = {} of UInt64 => Termisu::FFI::Context
  @@lock = Mutex.new
  @@next_handle = 1_u64

  def self.insert(context : Termisu::FFI::Context) : UInt64
    @@lock.synchronize do
      handle = @@next_handle
      @@next_handle += 1_u64
      @@contexts[handle] = context
      handle
    end
  end

  def self.fetch(handle : UInt64) : Termisu::FFI::Context?
    @@lock.synchronize { @@contexts[handle]? }
  end

  def self.delete(handle : UInt64) : Termisu::FFI::Context?
    @@lock.synchronize { @@contexts.delete(handle) }
  end
end
