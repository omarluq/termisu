require "../../spec_helper"

describe Termisu::FFI::Guards do
  it "returns yielded values and clears stale errors on success" do
    Termisu::FFI::ErrorState.set("stale")

    handle = Termisu::FFI::Guards.safe_handle { 42_u64 }
    status = Termisu::FFI::Guards.safe_status { Termisu::FFI::Status::Ok }
    value = Termisu::FFI::Guards.safe_u8 { 9_u8 }

    handle.should eq(42_u64)
    status.should eq(Termisu::FFI::Status::Ok.value)
    value.should eq(9_u8)
    Termisu::FFI::ErrorState.current.should eq("")
  end

  it "captures raised exceptions and returns fallbacks" do
    handle = Termisu::FFI::Guards.safe_handle { raise RuntimeError.new("handle exploded") }
    handle.should eq(0_u64)
    Termisu::FFI::ErrorState.current.should contain("RuntimeError: handle exploded")

    status = Termisu::FFI::Guards.safe_status { raise RuntimeError.new("status exploded") }
    status.should eq(Termisu::FFI::Status::Error.value)
    Termisu::FFI::ErrorState.current.should contain("RuntimeError: status exploded")

    value = Termisu::FFI::Guards.safe_u8(7_u8) { raise RuntimeError.new("u8 exploded") }
    value.should eq(7_u8)
    Termisu::FFI::ErrorState.current.should contain("RuntimeError: u8 exploded")
  end
end
