require "../spec_helper"

describe Termisu::Color do
  it "can be instantiated" do
    color = Termisu::Color.new
    color.should be_a(Termisu::Color)
  end
end
