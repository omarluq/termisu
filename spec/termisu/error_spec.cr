require "../spec_helper"

describe Termisu::Error do
  it "is an Exception" do
    error = Termisu::Error.new("test error")
    error.should be_a(Exception)
  end

  it "stores error message" do
    error = Termisu::Error.new("test error")
    error.message.should eq("test error")
  end
end
