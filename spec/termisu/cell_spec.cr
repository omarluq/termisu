require "../spec_helper"

describe Termisu::Cell do
  it "can be instantiated" do
    cell = Termisu::Cell.new
    cell.should be_a(Termisu::Cell)
  end
end
