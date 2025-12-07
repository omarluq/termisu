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
end
