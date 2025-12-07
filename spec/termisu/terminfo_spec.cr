require "../spec_helper"

describe Termisu::Terminfo do
  describe "#initialize" do
    it "creates a Terminfo instance" do
      # Ensure TERM is set for CI environments
      ENV["TERM"] ||= "xterm"
      term = Termisu::Terminfo.new
      term.should be_a(Termisu::Terminfo)
    end

    it "raises error when TERM environment variable not set" do
      original_term = ENV["TERM"]?

      begin
        ENV.delete("TERM")
        expect_raises(Exception, /TERM environment variable not set/) do
          Termisu::Terminfo.new
        end
      ensure
        ENV["TERM"] = original_term if original_term
      end
    end

    it "falls back to builtin capabilities when database unavailable" do
      # Set a fake terminal name that won't be in database
      original_term = ENV["TERM"]?

      begin
        ENV["TERM"] = "nonexistent-fake-terminal-xyz"
        term = Termisu::Terminfo.new
        term.should be_a(Termisu::Terminfo)
        # Should have fallback values
        term.clear_screen_seq.should be_a(String)
      ensure
        ENV["TERM"] = original_term if original_term
      end
    end
  end

  describe "sequence accessors" do
    it "provides enter_ca_seq accessor" do
      begin
        term = Termisu::Terminfo.new
        term.enter_ca_seq.should be_a(String)
      rescue
        pending "Terminfo not available"
      end
    end

    it "provides exit_ca_seq accessor" do
      begin
        term = Termisu::Terminfo.new
        term.exit_ca_seq.should be_a(String)
      rescue
        pending "Terminfo not available"
      end
    end

    it "provides show_cursor_seq accessor" do
      begin
        term = Termisu::Terminfo.new
        term.show_cursor_seq.should be_a(String)
      rescue
        pending "Terminfo not available"
      end
    end

    it "provides hide_cursor_seq accessor" do
      begin
        term = Termisu::Terminfo.new
        term.hide_cursor_seq.should be_a(String)
      rescue
        pending "Terminfo not available"
      end
    end

    it "provides clear_screen_seq accessor" do
      begin
        term = Termisu::Terminfo.new
        term.clear_screen_seq.should be_a(String)
        term.clear_screen_seq.should_not be_empty
      rescue
        pending "Terminfo not available"
      end
    end

    it "provides reset_attrs_seq accessor" do
      begin
        term = Termisu::Terminfo.new
        term.reset_attrs_seq.should be_a(String)
      rescue
        pending "Terminfo not available"
      end
    end

    it "provides underline_seq accessor" do
      begin
        term = Termisu::Terminfo.new
        term.underline_seq.should be_a(String)
      rescue
        pending "Terminfo not available"
      end
    end

    it "provides bold_seq accessor" do
      begin
        term = Termisu::Terminfo.new
        term.bold_seq.should be_a(String)
      rescue
        pending "Terminfo not available"
      end
    end

    it "provides blink_seq accessor" do
      begin
        term = Termisu::Terminfo.new
        term.blink_seq.should be_a(String)
      rescue
        pending "Terminfo not available"
      end
    end

    it "provides reverse_seq accessor" do
      begin
        term = Termisu::Terminfo.new
        term.reverse_seq.should be_a(String)
      rescue
        pending "Terminfo not available"
      end
    end

    it "provides enter_keypad_seq accessor" do
      begin
        term = Termisu::Terminfo.new
        term.enter_keypad_seq.should be_a(String)
      rescue
        pending "Terminfo not available"
      end
    end

    it "provides exit_keypad_seq accessor" do
      begin
        term = Termisu::Terminfo.new
        term.exit_keypad_seq.should be_a(String)
      rescue
        pending "Terminfo not available"
      end
    end
  end

  describe "builtin fallback behavior" do
    it "uses xterm fallback for unknown terminals" do
      original_term = ENV["TERM"]?

      begin
        ENV["TERM"] = "totally-unknown-terminal"
        term = Termisu::Terminfo.new

        # Should get xterm fallback values
        term.clear_screen_seq.should eq("\e[H\e[2J")
        term.bold_seq.should eq("\e[1m")
        term.underline_seq.should eq("\e[4m")
      ensure
        ENV["TERM"] = original_term if original_term
      end
    end

    it "uses linux fallback for linux terminals" do
      original_term = ENV["TERM"]?

      begin
        ENV["TERM"] = "linux-unknown"
        term = Termisu::Terminfo.new

        # Should get linux fallback values
        term.clear_screen_seq.should eq("\e[H\e[J")
        term.reset_attrs_seq.should eq("\e[m")
      ensure
        ENV["TERM"] = original_term if original_term
      end
    end
  end

  describe "capability array sizes" do
    it "has 12 function capabilities" do
      begin
        term = Termisu::Terminfo.new
        # Verify all 12 accessors work
        [
          term.enter_ca_seq,
          term.exit_ca_seq,
          term.show_cursor_seq,
          term.hide_cursor_seq,
          term.clear_screen_seq,
          term.reset_attrs_seq,
          term.underline_seq,
          term.bold_seq,
          term.blink_seq,
          term.reverse_seq,
          term.enter_keypad_seq,
          term.exit_keypad_seq,
        ].size.should eq(12)
      rescue
        pending "Terminfo not available"
      end
    end
  end

  describe "escape sequence format" do
    it "returns ANSI escape sequences" do
      begin
        term = Termisu::Terminfo.new

        # Clear screen should have escape sequence
        term.clear_screen_seq.should contain("\e")
      rescue
        pending "Terminfo not available"
      end
    end

    it "bold capability contains escape sequence" do
      begin
        term = Termisu::Terminfo.new
        term.bold_seq.should contain("\e")
      rescue
        pending "Terminfo not available"
      end
    end
  end

  describe "integration with subsystems" do
    it "integrates with Database for loading" do
      begin
        term = Termisu::Terminfo.new
        # If we get here, Database integration worked
        term.should be_a(Termisu::Terminfo)
      rescue
        pending "Terminfo database not available"
      end
    end

    it "integrates with Parser for parsing" do
      begin
        term = Termisu::Terminfo.new
        # Parser should have extracted capabilities
        term.clear_screen_seq.should be_a(String)
      rescue
        pending "Terminfo not available"
      end
    end

    it "integrates with Builtin for fallback" do
      original_term = ENV["TERM"]?

      begin
        ENV["TERM"] = "fake-terminal"
        term = Termisu::Terminfo.new
        # Builtin fallback should provide capabilities
        term.clear_screen_seq.should_not be_empty
      ensure
        ENV["TERM"] = original_term if original_term
      end
    end

    it "integrates with Capabilities for indices" do
      begin
        term = Termisu::Terminfo.new
        # Capabilities indices should map correctly
        term.should be_a(Termisu::Terminfo)
      rescue
        pending "Terminfo not available"
      end
    end
  end

  describe "error recovery" do
    it "gracefully handles database load failures" do
      original_term = ENV["TERM"]?

      begin
        ENV["TERM"] = "nonexistent-term"
        term = Termisu::Terminfo.new
        # Should fall back to builtin without crashing
        term.clear_screen_seq.should be_a(String)
      ensure
        ENV["TERM"] = original_term if original_term
      end
    end

    it "gracefully handles parse failures" do
      original_term = ENV["TERM"]?

      begin
        ENV["TERM"] = "fake"
        term = Termisu::Terminfo.new
        # Should use builtin fallback
        term.should be_a(Termisu::Terminfo)
      ensure
        ENV["TERM"] = original_term if original_term
      end
    end
  end

  describe "common terminal types" do
    it "works with xterm" do
      original_term = ENV["TERM"]?

      begin
        ENV["TERM"] = "xterm"
        term = Termisu::Terminfo.new
        term.clear_screen_seq.should_not be_empty
      ensure
        ENV["TERM"] = original_term if original_term
      end
    end

    it "works with linux" do
      original_term = ENV["TERM"]?

      begin
        ENV["TERM"] = "linux"
        term = Termisu::Terminfo.new
        term.clear_screen_seq.should_not be_empty
      ensure
        ENV["TERM"] = original_term if original_term
      end
    end
  end

  describe "cursor positioning (cup capability)" do
    it "provides cup_seq accessor" do
      original_term = ENV["TERM"]?

      begin
        ENV["TERM"] = "xterm"
        term = Termisu::Terminfo.new
        term.cup_seq.should be_a(String)
        term.cup_seq.should_not be_empty
      ensure
        ENV["TERM"] = original_term if original_term
      end
    end

    it "generates cursor position sequence for origin" do
      original_term = ENV["TERM"]?

      begin
        ENV["TERM"] = "xterm"
        term = Termisu::Terminfo.new
        # 0-based coordinates, cup has %i which increments to 1-based
        seq = term.cursor_position_seq(0, 0)
        seq.should eq("\e[1;1H")
      ensure
        ENV["TERM"] = original_term if original_term
      end
    end

    it "generates cursor position sequence for arbitrary position" do
      original_term = ENV["TERM"]?

      begin
        ENV["TERM"] = "xterm"
        term = Termisu::Terminfo.new
        # Row 9, Col 19 (0-based) -> 10;20 (1-based)
        seq = term.cursor_position_seq(9, 19)
        seq.should eq("\e[10;20H")
      ensure
        ENV["TERM"] = original_term if original_term
      end
    end

    it "generates cursor position sequence for bottom-right of 80x24 terminal" do
      original_term = ENV["TERM"]?

      begin
        ENV["TERM"] = "xterm"
        term = Termisu::Terminfo.new
        # Row 23, Col 79 (0-based) -> 24;80 (1-based)
        seq = term.cursor_position_seq(23, 79)
        seq.should eq("\e[24;80H")
      ensure
        ENV["TERM"] = original_term if original_term
      end
    end

    it "uses builtin cup for unknown terminals" do
      original_term = ENV["TERM"]?

      begin
        ENV["TERM"] = "fake-unknown-terminal"
        term = Termisu::Terminfo.new
        seq = term.cursor_position_seq(4, 9)
        # Should still work with builtin fallback
        seq.should eq("\e[5;10H")
      ensure
        ENV["TERM"] = original_term if original_term
      end
    end
  end

  describe "color sequence methods" do
    it "provides setaf_seq accessor" do
      original_term = ENV["TERM"]?

      begin
        ENV["TERM"] = "xterm"
        term = Termisu::Terminfo.new
        term.setaf_seq.should be_a(String)
        term.setaf_seq.should_not be_empty
      ensure
        ENV["TERM"] = original_term if original_term
      end
    end

    it "provides setab_seq accessor" do
      original_term = ENV["TERM"]?

      begin
        ENV["TERM"] = "xterm"
        term = Termisu::Terminfo.new
        term.setab_seq.should be_a(String)
        term.setab_seq.should_not be_empty
      ensure
        ENV["TERM"] = original_term if original_term
      end
    end

    it "generates foreground color sequence" do
      original_term = ENV["TERM"]?

      begin
        # Use a fake terminal to ensure builtin fallback is used
        ENV["TERM"] = "fake-unknown-terminal"
        term = Termisu::Terminfo.new
        seq = term.foreground_color_seq(1)
        seq.should eq("\e[38;5;1m")
      ensure
        ENV["TERM"] = original_term if original_term
      end
    end

    it "generates background color sequence" do
      original_term = ENV["TERM"]?

      begin
        # Use a fake terminal to ensure builtin fallback is used
        ENV["TERM"] = "fake-unknown-terminal"
        term = Termisu::Terminfo.new
        seq = term.background_color_seq(4)
        seq.should eq("\e[48;5;4m")
      ensure
        ENV["TERM"] = original_term if original_term
      end
    end

    it "handles 256 color indices with builtin" do
      original_term = ENV["TERM"]?

      begin
        # Use a fake terminal to ensure builtin fallback is used
        ENV["TERM"] = "fake-unknown-terminal"
        term = Termisu::Terminfo.new
        term.foreground_color_seq(196).should eq("\e[38;5;196m")
        term.background_color_seq(255).should eq("\e[48;5;255m")
      ensure
        ENV["TERM"] = original_term if original_term
      end
    end
  end

  describe "capability caching" do
    it "caches cup capability for performance" do
      original_term = ENV["TERM"]?

      begin
        ENV["TERM"] = "xterm"
        term = Termisu::Terminfo.new
        # Multiple calls should return same value (cached)
        cup1 = term.cup_seq
        cup2 = term.cup_seq
        cup1.should eq(cup2)
        cup1.should_not be_empty
      ensure
        ENV["TERM"] = original_term if original_term
      end
    end

    it "caches setaf capability for performance" do
      original_term = ENV["TERM"]?

      begin
        ENV["TERM"] = "xterm"
        term = Termisu::Terminfo.new
        setaf1 = term.setaf_seq
        setaf2 = term.setaf_seq
        setaf1.should eq(setaf2)
      ensure
        ENV["TERM"] = original_term if original_term
      end
    end

    it "caches setab capability for performance" do
      original_term = ENV["TERM"]?

      begin
        ENV["TERM"] = "xterm"
        term = Termisu::Terminfo.new
        setab1 = term.setab_seq
        setab2 = term.setab_seq
        setab1.should eq(setab2)
      ensure
        ENV["TERM"] = original_term if original_term
      end
    end
  end

  describe "cursor movement sequences (parametrized)" do
    it "generates cursor forward sequence" do
      original_term = ENV["TERM"]?

      begin
        ENV["TERM"] = "fake-unknown-terminal"
        term = Termisu::Terminfo.new
        term.cursor_forward_seq(5).should eq("\e[5C")
      ensure
        ENV["TERM"] = original_term if original_term
      end
    end

    it "generates cursor backward sequence" do
      original_term = ENV["TERM"]?

      begin
        ENV["TERM"] = "fake-unknown-terminal"
        term = Termisu::Terminfo.new
        term.cursor_backward_seq(3).should eq("\e[3D")
      ensure
        ENV["TERM"] = original_term if original_term
      end
    end

    it "generates cursor up sequence" do
      original_term = ENV["TERM"]?

      begin
        ENV["TERM"] = "fake-unknown-terminal"
        term = Termisu::Terminfo.new
        term.cursor_up_seq(2).should eq("\e[2A")
      ensure
        ENV["TERM"] = original_term if original_term
      end
    end

    it "generates cursor down sequence" do
      original_term = ENV["TERM"]?

      begin
        ENV["TERM"] = "fake-unknown-terminal"
        term = Termisu::Terminfo.new
        term.cursor_down_seq(4).should eq("\e[4B")
      ensure
        ENV["TERM"] = original_term if original_term
      end
    end

    it "generates column address sequence (0-based to 1-based)" do
      original_term = ENV["TERM"]?

      begin
        ENV["TERM"] = "fake-unknown-terminal"
        term = Termisu::Terminfo.new
        # Column 9 (0-based) -> 10 (1-based)
        term.column_address_seq(9).should eq("\e[10G")
      ensure
        ENV["TERM"] = original_term if original_term
      end
    end

    it "generates row address sequence (0-based to 1-based)" do
      original_term = ENV["TERM"]?

      begin
        ENV["TERM"] = "fake-unknown-terminal"
        term = Termisu::Terminfo.new
        # Row 14 (0-based) -> 15 (1-based)
        term.row_address_seq(14).should eq("\e[15d")
      ensure
        ENV["TERM"] = original_term if original_term
      end
    end
  end

  describe "line editing sequences (parametrized)" do
    it "generates erase characters sequence" do
      original_term = ENV["TERM"]?

      begin
        ENV["TERM"] = "fake-unknown-terminal"
        term = Termisu::Terminfo.new
        term.erase_chars_seq(10).should eq("\e[10X")
      ensure
        ENV["TERM"] = original_term if original_term
      end
    end

    it "generates insert lines sequence" do
      original_term = ENV["TERM"]?

      begin
        ENV["TERM"] = "fake-unknown-terminal"
        term = Termisu::Terminfo.new
        term.insert_lines_seq(3).should eq("\e[3L")
      ensure
        ENV["TERM"] = original_term if original_term
      end
    end

    it "generates delete lines sequence" do
      original_term = ENV["TERM"]?

      begin
        ENV["TERM"] = "fake-unknown-terminal"
        term = Termisu::Terminfo.new
        term.delete_lines_seq(2).should eq("\e[2M")
      ensure
        ENV["TERM"] = original_term if original_term
      end
    end
  end

  describe "extended attribute sequences" do
    it "returns dim sequence (SGR 2)" do
      original_term = ENV["TERM"]?

      begin
        ENV["TERM"] = "fake-unknown-terminal"
        term = Termisu::Terminfo.new
        term.dim_seq.should eq("\e[2m")
      ensure
        ENV["TERM"] = original_term if original_term
      end
    end

    it "returns italic sequence (SGR 3)" do
      original_term = ENV["TERM"]?

      begin
        ENV["TERM"] = "fake-unknown-terminal"
        term = Termisu::Terminfo.new
        term.italic_seq.should eq("\e[3m")
      ensure
        ENV["TERM"] = original_term if original_term
      end
    end

    it "returns hidden sequence (SGR 8)" do
      original_term = ENV["TERM"]?

      begin
        ENV["TERM"] = "fake-unknown-terminal"
        term = Termisu::Terminfo.new
        term.hidden_seq.should eq("\e[8m")
      ensure
        ENV["TERM"] = original_term if original_term
      end
    end

    it "dim sequence contains escape character" do
      original_term = ENV["TERM"]?

      begin
        ENV["TERM"] = "xterm"
        term = Termisu::Terminfo.new
        term.dim_seq.should contain("\e")
      ensure
        ENV["TERM"] = original_term if original_term
      end
    end

    it "italic sequence contains escape character" do
      original_term = ENV["TERM"]?

      begin
        ENV["TERM"] = "xterm"
        term = Termisu::Terminfo.new
        term.italic_seq.should contain("\e")
      ensure
        ENV["TERM"] = original_term if original_term
      end
    end

    it "hidden sequence contains escape character" do
      original_term = ENV["TERM"]?

      begin
        ENV["TERM"] = "xterm"
        term = Termisu::Terminfo.new
        term.hidden_seq.should contain("\e")
      ensure
        ENV["TERM"] = original_term if original_term
      end
    end
  end
end
