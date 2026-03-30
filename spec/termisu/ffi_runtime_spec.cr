require "../spec_helper"

describe Termisu::FFI::Runtime do
  it "returns immediately when the runtime is already bootstrapped" do
    Termisu::FFI::Runtime.ensure_initialized
  end

  it "is safe to call repeatedly from multiple fibers once bootstrapped" do
    channel = Channel(Nil).new(4)

    4.times do
      spawn do
        Termisu::FFI::Runtime.ensure_initialized
        channel.send(nil)
      end
    end

    4.times { channel.receive }
  end
end
