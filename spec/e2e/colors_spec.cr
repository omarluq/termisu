require "./e2e_helper"

# Port of e2e/tests/colors.test.ts — drives bin/colors and asserts on section
# headers, rendered color blocks (█), hex codes, ordering, and a snapshot.
private def with_colors(&)
  requires_binary "bin/colors"
  Termisu::Testing.terminal("bin/colors", cols: 100, rows: 50) do |term|
    term.get_by_text(/ANSI-8 Colors/).should be_true
    yield term
  end
end

# Count the block glyphs on the row just below a section header.
private def blocks_below(term, label) : Int32
  pos = term.locate(label)
  pos.should_not be_nil
  return 0 unless pos
  term.row(pos[1] + 1).count('█')
end

describe "Colors example (e2e)" do
  describe "section headers" do
    it "shows all section headers in order" do
      with_colors do |term|
        labels = [
          "ANSI-8 Colors", "ANSI-256 Bright Colors:", "Color Cube", "Grayscale",
          "TrueColor", "Color Conversions:", "Hex Colors:", "Background Colors:",
        ]
        ys = labels.map do |label|
          pos = term.locate(label)
          pos.should_not be_nil
          pos.try(&.[](1)) || -1
        end
        ys.should eq(ys.sort)      # rendered top-to-bottom in order
        ys.each(&.should(be >= 0)) # every section present
      end
    end
  end

  describe "rendered color blocks" do
    it "renders ANSI-8 blocks (>= 8)" do
      with_colors { |term| blocks_below(term, "ANSI-8 Colors").should be >= 8 }
    end

    it "renders the color cube row (>= 36)" do
      with_colors { |term| blocks_below(term, "Color Cube").should be >= 36 }
    end

    it "renders the grayscale ramp (>= 24)" do
      with_colors { |term| blocks_below(term, "Grayscale").should be >= 24 }
    end

    it "renders the truecolor gradient (>= 30)" do
      with_colors { |term| blocks_below(term, "TrueColor").should be >= 30 }
    end
  end

  describe "hex colors" do
    %w[#FF0000 #00FF00 #0000FF #FFFF00 #FF00FF #00FFFF].each do |hex|
      it "shows #{hex}" do
        with_colors(&.get_by_text(hex).should(be_true))
      end
    end
  end

  describe "conversions and backgrounds" do
    it "describes the RGB→ANSI conversion" do
      with_colors do |term|
        term.get_by_text(/RGB.*ANSI-256.*ANSI-8/).should be_true
        term.get_by_text(/255.*128.*64/).should be_true
      end
    end

    it "shows text on colored backgrounds" do
      with_colors { |term| term.get_by_text(/Text with backgrounds/).should be_true }
    end
  end

  describe "visual snapshot" do
    it "matches the committed snapshot" do
      with_colors do |term|
        term.get_by_text("Hex Colors:").should be_true
        assert_snapshot(term, "colors")
      end
    end
  end
end
