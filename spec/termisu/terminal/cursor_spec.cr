require "../../spec_helper"

describe Termisu::Terminal::Cursor do
  describe "#visible?" do
    it "defaults to false" do
      cursor = Termisu::Terminal::Cursor.new
      cursor.visible?.should be_false
    end
  end

  describe "#x" do
    it "defaults to 0" do
      cursor = Termisu::Terminal::Cursor.new
      cursor.x.should eq 0
    end
  end

  describe "#y" do
    it "defaults to 0" do
      cursor = Termisu::Terminal::Cursor.new
      cursor.y.should eq 0
    end
  end
end
