require "../spec_helper"

describe Termisu::Attribute do
  describe "enum values" do
    it "has None attribute" do
      Termisu::Attribute::None.value.should eq(0)
    end

    it "has Bold attribute" do
      Termisu::Attribute::Bold.value.should eq(1)
    end

    it "has Underline attribute" do
      Termisu::Attribute::Underline.value.should eq(2)
    end

    it "has Reverse attribute" do
      Termisu::Attribute::Reverse.value.should eq(4)
    end

    it "has Blink attribute" do
      Termisu::Attribute::Blink.value.should eq(8)
    end

    it "has Dim attribute" do
      Termisu::Attribute::Dim.value.should eq(16)
    end

    it "has Cursive attribute" do
      Termisu::Attribute::Cursive.value.should eq(32)
    end

    it "has Hidden attribute" do
      Termisu::Attribute::Hidden.value.should eq(64)
    end

    it "has Strikethrough attribute" do
      Termisu::Attribute::Strikethrough.value.should eq(128)
    end
  end

  describe "flag combinations" do
    it "can combine Bold and Underline" do
      attr = Termisu::Attribute::Bold | Termisu::Attribute::Underline
      attr.bold?.should be_true
      attr.underline?.should be_true
      attr.reverse?.should be_false
    end

    it "can combine multiple attributes" do
      attr = Termisu::Attribute::Bold | Termisu::Attribute::Underline | Termisu::Attribute::Reverse
      attr.bold?.should be_true
      attr.underline?.should be_true
      attr.reverse?.should be_true
      attr.blink?.should be_false
    end

    it "can check for None attribute" do
      attr = Termisu::Attribute::None
      attr.bold?.should be_false
      attr.underline?.should be_false
      attr.reverse?.should be_false
    end

    it "can combine with Strikethrough" do
      attr = Termisu::Attribute::Bold | Termisu::Attribute::Strikethrough
      attr.bold?.should be_true
      attr.strikethrough?.should be_true
      attr.underline?.should be_false
    end

    it "can combine all attributes" do
      attr = Termisu::Attribute::Bold | Termisu::Attribute::Underline |
             Termisu::Attribute::Reverse | Termisu::Attribute::Blink |
             Termisu::Attribute::Dim | Termisu::Attribute::Cursive |
             Termisu::Attribute::Hidden | Termisu::Attribute::Strikethrough
      attr.bold?.should be_true
      attr.underline?.should be_true
      attr.reverse?.should be_true
      attr.blink?.should be_true
      attr.dim?.should be_true
      attr.cursive?.should be_true
      attr.hidden?.should be_true
      attr.strikethrough?.should be_true
    end
  end
end
