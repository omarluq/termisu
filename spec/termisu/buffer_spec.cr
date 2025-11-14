require "../spec_helper"

describe Termisu::Buffer do
  it "can be instantiated" do
    buffer = Termisu::Buffer.new
    buffer.should be_a(Termisu::Buffer)
  end
end
