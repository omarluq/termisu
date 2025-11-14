require "../spec_helper"

describe Termisu::InputMode do
  it "can be instantiated" do
    input_mode = Termisu::InputMode.new
    input_mode.should be_a(Termisu::InputMode)
  end
end
