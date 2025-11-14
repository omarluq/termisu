require "../spec_helper"

describe Termisu::Event do
  it "can be instantiated" do
    event = Termisu::Event.new
    event.should be_a(Termisu::Event)
  end
end
