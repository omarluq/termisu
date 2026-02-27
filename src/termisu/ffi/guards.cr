module Termisu::FFI::Guards
  def self.safe_handle(& : -> UInt64) : UInt64
    Termisu::FFI::Runtime.ensure_initialized
    Termisu::FFI::ErrorState.clear
    yield
  rescue ex
    Termisu::FFI::ErrorState.set(Termisu::FFI::ErrorState.format(ex))
    0_u64
  end

  def self.safe_status(& : -> Termisu::FFI::Status) : Int32
    Termisu::FFI::Runtime.ensure_initialized
    Termisu::FFI::ErrorState.clear
    yield.value
  rescue ex
    Termisu::FFI::ErrorState.set(Termisu::FFI::ErrorState.format(ex))
    Termisu::FFI::Status::Error.value
  end

  def self.safe_u8(default : UInt8 = 0_u8, & : -> UInt8) : UInt8
    Termisu::FFI::Runtime.ensure_initialized
    Termisu::FFI::ErrorState.clear
    yield
  rescue ex
    Termisu::FFI::ErrorState.set(Termisu::FFI::ErrorState.format(ex))
    default
  end
end
