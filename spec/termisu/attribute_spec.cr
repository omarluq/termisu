require "../spec_helper"

describe Termisu::Attribute do
  it "can be instantiated" do
    attribute = Termisu::Attribute.new
    attribute.should be_a(Termisu::Attribute)
  end
end
