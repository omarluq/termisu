require "../../spec_helper"

# Regression spec pinning the cursor_position_seq fast path (direct string
# interpolation for the standard ANSI cup capability) to tparm output.
describe Termisu::Terminfo do
  describe "#cursor_position_seq fast-path equivalence" do
    it "matches Tparm.process of the raw cup capability for sample coordinates" do
      original_term = ENV["TERM"]?

      begin
        ENV["TERM"] = "xterm"
        term = Termisu::Terminfo.new

        [{0, 0}, {9, 19}, {23, 79}, {999, 999}].each do |(row, col)|
          expected = Termisu::Terminfo::Tparm.process(term.cup_seq, row, col)
          term.cursor_position_seq(row, col).should eq(expected)
        end
      ensure
        if original_term
          ENV["TERM"] = original_term
        else
          ENV.delete("TERM")
        end
      end
    end

    it "produces the expected sequences for the standard cup template" do
      original_term = ENV["TERM"]?

      begin
        ENV["TERM"] = "xterm"
        term = Termisu::Terminfo.new
        term.cursor_position_seq(0, 0).should eq("\e[1;1H")
        term.cursor_position_seq(23, 79).should eq("\e[24;80H")
        term.cursor_position_seq(999, 999).should eq("\e[1000;1000H")
      ensure
        if original_term
          ENV["TERM"] = original_term
        else
          ENV.delete("TERM")
        end
      end
    end
  end
end
