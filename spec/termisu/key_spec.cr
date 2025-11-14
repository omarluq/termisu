require "../spec_helper"

describe Termisu::Key do
  it "can be instantiated" do
    key = Termisu::Key.new
    key.should be_a(Termisu::Key)
  end
end
