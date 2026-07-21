require "../../spec_helper"

# Terminal#apply_sgr coalesces a full style transition into one combined SGR
# sequence (\e[p1;p2;...m). Attribute removal uses the ECMA-48 selective off
# codes (22/23/24/25/27/28/29) so colors survive attribute drops.
describe "Terminal#apply_sgr (combined SGR emission)" do
  it "emits attributes and colors as a single combined sequence" do
    terminal = CaptureTerminal.new(sync_updates: false)

    terminal.apply_sgr(
      Termisu::Color.red, Termisu::Color.blue, Termisu::Attribute::Bold,
      nil, nil, Termisu::Attribute::None
    )

    terminal.writes.should eq(["\e[1;31;44m"])
  ensure
    terminal.try &.close
  end

  it "emits selective off codes without touching unchanged colors" do
    terminal = CaptureTerminal.new(sync_updates: false)
    terminal.apply_sgr(
      Termisu::Color.red, Termisu::Color.default, Termisu::Attribute::Bold | Termisu::Attribute::Underline,
      nil, nil, Termisu::Attribute::None
    )
    terminal.clear_captured

    terminal.apply_sgr(
      Termisu::Color.red, Termisu::Color.default, Termisu::Attribute::None,
      Termisu::Color.red, Termisu::Color.default, Termisu::Attribute::Bold | Termisu::Attribute::Underline
    )

    # No sgr0, no color re-emission - just intensity-off and underline-off.
    terminal.writes.should eq(["\e[22;24m"])
  ensure
    terminal.try &.close
  end

  it "re-emits dim after SGR 22 when only bold is removed" do
    terminal = CaptureTerminal.new(sync_updates: false)
    both = Termisu::Attribute::Bold | Termisu::Attribute::Dim
    terminal.apply_sgr(
      Termisu::Color.white, Termisu::Color.default, both,
      nil, nil, Termisu::Attribute::None
    )
    terminal.clear_captured

    terminal.apply_sgr(
      Termisu::Color.white, Termisu::Color.default, Termisu::Attribute::Dim,
      Termisu::Color.white, Termisu::Color.default, both
    )

    # SGR 22 clears bold AND dim, so dim must be re-applied.
    terminal.writes.should eq(["\e[22;2m"])
  ensure
    terminal.try &.close
  end

  it "re-emits bold after SGR 22 when only dim is removed" do
    terminal = CaptureTerminal.new(sync_updates: false)
    both = Termisu::Attribute::Bold | Termisu::Attribute::Dim
    terminal.apply_sgr(
      Termisu::Color.white, Termisu::Color.default, both,
      nil, nil, Termisu::Attribute::None
    )
    terminal.clear_captured

    terminal.apply_sgr(
      Termisu::Color.white, Termisu::Color.default, Termisu::Attribute::Bold,
      Termisu::Color.white, Termisu::Color.default, both
    )

    terminal.writes.should eq(["\e[22;1m"])
  ensure
    terminal.try &.close
  end

  it "covers every off code for the remaining attributes" do
    terminal = CaptureTerminal.new(sync_updates: false)
    all = Termisu::Attribute::Cursive | Termisu::Attribute::Underline |
          Termisu::Attribute::Blink | Termisu::Attribute::Reverse |
          Termisu::Attribute::Hidden | Termisu::Attribute::Strikethrough
    terminal.apply_sgr(
      Termisu::Color.white, Termisu::Color.default, all,
      nil, nil, Termisu::Attribute::None
    )
    terminal.clear_captured

    terminal.apply_sgr(
      Termisu::Color.white, Termisu::Color.default, Termisu::Attribute::None,
      Termisu::Color.white, Termisu::Color.default, all
    )

    terminal.writes.should eq(["\e[23;24;25;27;28;29m"])
  ensure
    terminal.try &.close
  end

  it "emits true-color parameters inside the combined sequence" do
    terminal = CaptureTerminal.new(sync_updates: false)

    terminal.apply_sgr(
      Termisu::Color.rgb(1, 2, 3), Termisu::Color.rgb(255, 128, 0), Termisu::Attribute::None,
      nil, nil, Termisu::Attribute::None
    )

    terminal.writes.should eq(["\e[38;2;1;2;3;48;2;255;128;0m"])
  ensure
    terminal.try &.close
  end

  it "emits ansi256 parameters inside the combined sequence" do
    terminal = CaptureTerminal.new(sync_updates: false)

    terminal.apply_sgr(
      Termisu::Color.ansi256(208), Termisu::Color.ansi256(21), Termisu::Attribute::None,
      nil, nil, Termisu::Attribute::None
    )

    terminal.writes.should eq(["\e[38;5;208;48;5;21m"])
  ensure
    terminal.try &.close
  end

  it "emits default-color parameters 39/49" do
    terminal = CaptureTerminal.new(sync_updates: false)
    terminal.apply_sgr(
      Termisu::Color.red, Termisu::Color.blue, Termisu::Attribute::None,
      nil, nil, Termisu::Attribute::None
    )
    terminal.clear_captured

    terminal.apply_sgr(
      Termisu::Color.default, Termisu::Color.default, Termisu::Attribute::None,
      Termisu::Color.red, Termisu::Color.blue, Termisu::Attribute::None
    )

    terminal.writes.should eq(["\e[39;49m"])
  ensure
    terminal.try &.close
  end

  it "emits nothing when the transition matches the terminal's cached style" do
    terminal = CaptureTerminal.new(sync_updates: false)
    terminal.apply_sgr(
      Termisu::Color.red, Termisu::Color.default, Termisu::Attribute::Bold,
      nil, nil, Termisu::Attribute::None
    )
    terminal.clear_captured

    # Caller believes the style is unknown, but the terminal cache is current.
    terminal.apply_sgr(
      Termisu::Color.red, Termisu::Color.default, Termisu::Attribute::Bold,
      nil, nil, Termisu::Attribute::None
    )

    terminal.writes.should be_empty
  ensure
    terminal.try &.close
  end

  it "renders cell styles through the combined emitter" do
    terminal = CaptureTerminal.new(sync_updates: false)

    terminal.set_cell(0, 0, 'X', fg: Termisu::Color.red, bg: Termisu::Color.blue, attr: Termisu::Attribute::Bold)
    terminal.render

    terminal.writes.should contain("\e[1;31;44m")
    terminal.writes.should contain("X")
  ensure
    terminal.try &.close
  end
end

# The decomposed default lives in Renderer and is covered by
# spec/termisu/renderer_spec.cr; this suite pins Terminal's guard that
# routes non-standard terminfo through it.
describe "Terminal#apply_sgr (non-standard terminfo fallback)" do
  it "falls back to decomposed emission when terminfo attributes are non-standard" do
    terminal = CaptureTerminal.new(sync_updates: false, terminfo: NonStandardAttrsTerminfo.new)

    terminal.apply_sgr(
      Termisu::Color.red, Termisu::Color.default, Termisu::Attribute::Bold,
      nil, nil, Termisu::Attribute::None
    )
    terminal.writes.size.should be > 1 # combined emission is always one write
    terminal.clear_captured

    terminal.apply_sgr(
      Termisu::Color.red, Termisu::Color.default, Termisu::Attribute::None,
      Termisu::Color.red, Termisu::Color.default, Termisu::Attribute::Bold
    )

    # The decomposed fallback removes attributes via a full reset and never
    # emits the ECMA-48 selective off codes the combined emitter uses.
    terminal.writes.none?(&.includes?("22")).should be_true
    terminal.writes.size.should be > 1
  ensure
    terminal.try &.close
  end
end

# Forces Terminal#apply_sgr's non-standard-terminfo guard: real terminfo
# databases (plus the builtin backfill) always report ECMA-standard attribute
# sequences, so the fallback branch is only reachable with an injected stub.
private class NonStandardAttrsTerminfo < Termisu::Terminfo
  def attrs_are_standard? : Bool
    false
  end
end
