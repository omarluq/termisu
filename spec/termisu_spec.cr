require "./spec_helper"

describe Termisu do
  it "has a version number" do
    Termisu::VERSION.should_not be_nil
  end

  it "can be instantiated" do
    termisu = Termisu.new
    termisu.should be_a(Termisu)
  end

  describe "#width" do
    it "returns 0" do
      termisu = Termisu.new
      termisu.width.should eq(0)
    end
  end

  describe "#height" do
    it "returns 0" do
      termisu = Termisu.new
      termisu.height.should eq(0)
    end
  end
end
