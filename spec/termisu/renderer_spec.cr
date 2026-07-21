require "../spec_helper"

# The default Renderer#apply_sgr decomposes into the granular methods with the
# legacy reset-then-reapply semantics; generic renderer subclasses and
# Terminal's non-standard-terminfo fallback both run this branch.
describe "Renderer#apply_sgr (default decomposed emission)" do
  it "resets and reapplies when attributes are removed" do
    renderer = MockRenderer.new
    both = Termisu::Attribute::Bold | Termisu::Attribute::Underline

    renderer.apply_sgr(
      Termisu::Color.red, Termisu::Color.blue, Termisu::Attribute::Underline,
      Termisu::Color.red, Termisu::Color.blue, both
    )

    # Removal forces a full reset, which clears colors, so the surviving
    # attribute and both colors must be re-emitted.
    renderer.reset_count.should eq(1)
    renderer.underline_count.should eq(1)
    renderer.bold_count.should eq(0)
    renderer.fg_calls.should eq([Termisu::Color.red])
    renderer.bg_calls.should eq([Termisu::Color.blue])
  end

  it "adds attributes without a reset when none are removed" do
    renderer = MockRenderer.new

    renderer.apply_sgr(
      Termisu::Color.red, Termisu::Color.default, Termisu::Attribute::Bold | Termisu::Attribute::Underline,
      Termisu::Color.red, Termisu::Color.default, Termisu::Attribute::Bold
    )

    renderer.reset_count.should eq(0)
    renderer.underline_count.should eq(1)
    renderer.bold_count.should eq(0)
    renderer.fg_calls.should be_empty
    renderer.bg_calls.should be_empty
  end
end
