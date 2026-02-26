require "../spec_helper"

describe "Termisu version constants (BUG-007 regression)" do
  it "defines VERSION as a non-empty string" do
    Termisu::VERSION.should be_a(String)
    Termisu::VERSION.empty?.should be_false
  end

  it "defines VERSION_MAJOR as an integer" do
    Termisu::VERSION_MAJOR.should be_a(Int32)
    Termisu::VERSION_MAJOR.should be >= 0
  end

  it "defines VERSION_MINOR as an integer" do
    Termisu::VERSION_MINOR.should be_a(Int32)
    Termisu::VERSION_MINOR.should be >= 0
  end

  it "defines VERSION_PATCH as an integer" do
    Termisu::VERSION_PATCH.should be_a(Int32)
    Termisu::VERSION_PATCH.should be >= 0
  end

  it "VERSION matches MAJOR.MINOR.PATCH format" do
    version = Termisu::VERSION
    # VERSION should start with "MAJOR.MINOR.PATCH"
    version.should match(/^\d+\.\d+\.\d+/)
    # Verify components match
    parts = version.split("-")[0].split(".")
    parts[0].to_i.should eq(Termisu::VERSION_MAJOR)
    parts[1].to_i.should eq(Termisu::VERSION_MINOR)
    parts[2].to_i.should eq(Termisu::VERSION_PATCH)
  end

  it "VERSION_STATE is nil or a non-empty string" do
    state = Termisu::VERSION_STATE
    if state
      state.should be_a(String)
      state.as(String).empty?.should be_false
    end
  end
end
