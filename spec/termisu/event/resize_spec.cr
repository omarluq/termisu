require "../../spec_helper"

describe Termisu::Event::Resize do
  describe ".new" do
    it "creates a resize event with dimensions" do
      event = Termisu::Event::Resize.new(80, 24)
      event.width.should eq(80)
      event.height.should eq(24)
    end

    it "creates a resize event with nil old dimensions by default" do
      event = Termisu::Event::Resize.new(80, 24)
      event.old_width.should be_nil
      event.old_height.should be_nil
    end

    it "creates a resize event with old dimensions" do
      event = Termisu::Event::Resize.new(120, 40, 80, 24)
      event.width.should eq(120)
      event.height.should eq(40)
      event.old_width.should eq(80)
      event.old_height.should eq(24)
    end

    it "creates a resize event with named parameters" do
      event = Termisu::Event::Resize.new(
        width: 100,
        height: 50,
        old_width: 80,
        old_height: 40,
      )
      event.width.should eq(100)
      event.height.should eq(50)
      event.old_width.should eq(80)
      event.old_height.should eq(40)
    end
  end

  describe "#changed?" do
    it "returns true when old dimensions are nil" do
      event = Termisu::Event::Resize.new(80, 24)
      event.changed?.should be_true
    end

    it "returns true when only old_width is nil" do
      event = Termisu::Event::Resize.new(80, 24, nil, 24)
      event.changed?.should be_true
    end

    it "returns true when only old_height is nil" do
      event = Termisu::Event::Resize.new(80, 24, 80, nil)
      event.changed?.should be_true
    end

    it "returns true when width changed" do
      event = Termisu::Event::Resize.new(120, 24, 80, 24)
      event.changed?.should be_true
    end

    it "returns true when height changed" do
      event = Termisu::Event::Resize.new(80, 40, 80, 24)
      event.changed?.should be_true
    end

    it "returns true when both dimensions changed" do
      event = Termisu::Event::Resize.new(120, 40, 80, 24)
      event.changed?.should be_true
    end

    it "returns false when dimensions are the same" do
      event = Termisu::Event::Resize.new(80, 24, 80, 24)
      event.changed?.should be_false
    end
  end

  describe "backward compatibility" do
    it "works with the original two-argument constructor" do
      # Ensure existing code that creates Resize events still works
      event = Termisu::Event::Resize.new(80, 24)
      event.width.should eq(80)
      event.height.should eq(24)
    end
  end
end
