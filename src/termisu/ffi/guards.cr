module Termisu::FFI::Guards
  def self.safe_handle(& : -> UInt64) : UInt64
    with_error_fallback(0_u64) { yield }
  end

  def self.safe_status(& : -> Termisu::FFI::Status) : Int32
    with_error_fallback(Termisu::FFI::Status::Error) { yield }.value
  end

  def self.safe_u8(default : UInt8 = 0_u8, & : -> UInt8) : UInt8
    with_error_fallback(default) { yield }
  end

  private def self.with_error_fallback(default : T, & : -> T) : T forall T
    Termisu::FFI::Runtime.ensure_initialized
    Termisu::FFI::ErrorState.clear
    yield
  rescue ex
    Termisu::FFI::ErrorState.set(Termisu::FFI::ErrorState.format(ex))
    default
  end
end
