require "./e2e_helper"

# Port of e2e/tests/showcase.test.ts — drives bin/showcase.
# Note: no full-screen snapshot here — the showcase has a live spinner + frame
# counter, so a deterministic snapshot isn't meaningful (the colors suite covers
# the snapshot path against a static screen).
private def with_showcase(&)
  requires_binary "bin/showcase"
  Termisu::Testing.terminal("bin/showcase", cols: 100, rows: 50) do |term|
    term.get_by_text("TERMISU SHOWCASE").should be_true
    yield term
  end
end

describe "Showcase application (e2e)" do
  describe "header" do
    it "renders the title, Unicode box and subtitle" do
      with_showcase do |term|
        term.get_by_text("TERMISU SHOWCASE").should be_true
        term.get_by_text(/╔.*═.*╗/).should be_true
        term.get_by_text(/Pure Crystal Terminal UI Library/).should be_true
        term.get_by_text(/\d+x\d+/).should be_true
      end
    end
  end

  describe "sections" do
    ["ANSI-8 Colors:", "Bright Colors:", "Text Attributes:", "Combined:",
     "ANSI-256 Palette:", "Hex Colors:", "Background Colors:"].each do |label|
      it "renders the #{label} section" do
        with_showcase { |term| term.get_by_text(label).should be_true }
      end
    end

    it "renders text attributes and combinations" do
      with_showcase do |term|
        term.get_by_text("Normal").should be_true
        term.get_by_text("Bold+Underline").should be_true
        term.get_by_text("Reverse").should be_true
        term.get_by_text("Strike").should be_true
        term.get_by_text("Dim+Italic").should be_true
      end
    end

    it "renders truecolor + conversion labels" do
      with_showcase do |term|
        term.get_by_text(/RGB TrueColor.*colors/).should be_true
        term.get_by_text(/16\.7M colors/).should be_true
        term.get_by_text(/Color Conversion.*RGB.*ANSI/).should be_true
        term.get_by_text("RGB:").should be_true
        term.get_by_text("256:").should be_true
        term.get_by_text("8:").should be_true
      end
    end

    it "shows hex color values and backgrounds" do
      with_showcase do |term|
        %w[#FF0000 #00FF00 #0000FF #FFFF00 #FF00FF #00FFFF].each do |hex|
          term.get_by_text(hex).should be_true
        end
        term.get_by_text(/Text on colored backgrounds/).should be_true
      end
    end
  end

  describe "interactive section" do
    it "shows the quit hint, running status and spinner" do
      with_showcase do |term|
        term.get_by_text(/Press 'q' to quit/).should be_true
        term.get_by_text(/Running.*Frame/).should be_true
        term.get_by_text(/[⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏]/).should be_true
      end
    end

    it "echoes a key press with byte and hex" do
      with_showcase do |term|
        term.write("a")
        term.get_by_text(/Key:.*'a'/).should be_true
        term.get_by_text(/byte=97/).should be_true
        term.get_by_text(/hex=0x61/).should be_true
      end
    end

    it "handles a number key" do
      with_showcase do |term|
        term.write("5")
        term.get_by_text(/Key:.*'5'/).should be_true
      end
    end
  end

  describe "layout snapshot" do
    it "matches the snapshot (spinner/frame/dots masked)" do
      with_showcase do |term|
        term.get_by_text(/Running.*Frame/).should be_true # status line rendered
        assert_snapshot(term, "showcase", mask: [
          /[⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏]/, # spinner glyph
          /Frame \d+/,    # frame counter
          /●+/,           # animated status dots
        ])
      end
    end
  end

  describe "exit handling" do
    it "shows the goodbye message on 'q'" do
      with_showcase do |term|
        term.write("q")
        term.get_by_text(/Goodbye/).should be_true
        term.get_by_text(/Termisu/).should be_true
      end
    end

    it "exits on uppercase 'Q'" do
      with_showcase do |term|
        term.write("Q")
        term.get_by_text(/Goodbye/).should be_true
      end
    end
  end
end
