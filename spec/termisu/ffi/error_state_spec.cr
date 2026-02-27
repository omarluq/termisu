require "../../spec_helper"

describe Termisu::FFI::ErrorState do
  it "stores and clears per-thread error text" do
    Termisu::FFI::ErrorState.clear
    Termisu::FFI::ErrorState.current.should eq("")

    Termisu::FFI::ErrorState.set("boom")
    Termisu::FFI::ErrorState.current.should eq("boom")

    Termisu::FFI::ErrorState.clear
    Termisu::FFI::ErrorState.current.should eq("")
  end

  it "formats exceptions with and without messages" do
    Termisu::FFI::ErrorState.format(RuntimeError.new("broken")).should eq("RuntimeError: broken")
    Termisu::FFI::ErrorState.format(Exception.new).should eq("Exception")
  end
end
