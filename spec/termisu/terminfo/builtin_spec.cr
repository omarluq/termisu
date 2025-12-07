require "../../spec_helper"

describe Termisu::Terminfo::Builtin do
  describe ".funcs_for" do
    context "with xterm terminal" do
      it "returns XTERM_FUNCS for xterm" do
        funcs = Termisu::Terminfo::Builtin.funcs_for("xterm")
        funcs.should be_a(Array(String))
        funcs.size.should eq(15) # Includes setaf, setab, and cup
      end

      it "returns XTERM_FUNCS for xterm-256color" do
        funcs = Termisu::Terminfo::Builtin.funcs_for("xterm-256color")
        funcs.size.should eq(15)        # Includes setaf, setab, and cup
        funcs[0].should eq("\e[?1049h") # enter_ca
      end

      it "returns XTERM_FUNCS for xterm-color" do
        funcs = Termisu::Terminfo::Builtin.funcs_for("xterm-color")
        funcs.size.should eq(15) # Includes setaf, setab, and cup
      end
    end

    context "with linux terminal" do
      it "returns LINUX_FUNCS for linux" do
        funcs = Termisu::Terminfo::Builtin.funcs_for("linux")
        funcs.should be_a(Array(String))
        funcs.size.should eq(15) # Includes setaf, setab, and cup
      end

      it "has empty strings for enter/exit_ca on linux" do
        funcs = Termisu::Terminfo::Builtin.funcs_for("linux")
        funcs[0].should eq("") # enter_ca
        funcs[1].should eq("") # exit_ca
      end

      it "has correct show_cursor sequence for linux" do
        funcs = Termisu::Terminfo::Builtin.funcs_for("linux")
        funcs[2].should eq("\e[?25h\e[?0c")
      end
    end

    context "escape sequences" do
      it "contains valid ANSI escape codes for xterm" do
        funcs = Termisu::Terminfo::Builtin.funcs_for("xterm")

        funcs[2].should eq("\e[?12l\e[?25h") # show_cursor
        funcs[3].should eq("\e[?25l")        # hide_cursor
        funcs[4].should eq("\e[H\e[2J")      # clear_screen
        funcs[5].should eq("\e[m\e(B")       # sgr0
        funcs[6].should eq("\e[4m")          # underline
        funcs[7].should eq("\e[1m")          # bold
        funcs[8].should eq("\e[5m")          # blink
        funcs[9].should eq("\e[7m")          # reverse
      end

      it "contains valid escape codes for linux" do
        funcs = Termisu::Terminfo::Builtin.funcs_for("linux")

        funcs[4].should eq("\e[H\e[J") # clear_screen
        funcs[5].should eq("\e[m")     # sgr0
        funcs[6].should eq("\e[4m")    # underline
        funcs[7].should eq("\e[1m")    # bold
      end
    end
  end

  describe ".keys_for" do
    context "with xterm terminal" do
      it "returns XTERM_KEYS for xterm" do
        keys = Termisu::Terminfo::Builtin.keys_for("xterm")
        keys.should be_a(Array(String))
        keys.size.should eq(22)
      end

      it "contains function key sequences" do
        keys = Termisu::Terminfo::Builtin.keys_for("xterm")

        keys[0].should eq("\eOP")   # F1
        keys[1].should eq("\eOQ")   # F2
        keys[2].should eq("\eOR")   # F3
        keys[3].should eq("\eOS")   # F4
        keys[4].should eq("\e[15~") # F5
      end

      it "contains navigation key sequences" do
        keys = Termisu::Terminfo::Builtin.keys_for("xterm")

        keys[12].should eq("\e[2~") # Insert
        keys[13].should eq("\e[3~") # Delete
        keys[14].should eq("\e[H")  # Home
        keys[15].should eq("\e[F")  # End
        keys[16].should eq("\e[5~") # PgUp
        keys[17].should eq("\e[6~") # PgDn
      end

      it "contains arrow key sequences" do
        keys = Termisu::Terminfo::Builtin.keys_for("xterm")

        keys[18].should eq("\e[A") # Up
        keys[19].should eq("\e[B") # Down
        keys[20].should eq("\e[D") # Left
        keys[21].should eq("\e[C") # Right
      end
    end

    context "with linux terminal" do
      it "returns LINUX_KEYS for linux" do
        keys = Termisu::Terminfo::Builtin.keys_for("linux")
        keys.should be_a(Array(String))
        keys.size.should eq(22)
      end

      it "has different F1-F5 sequences than xterm" do
        keys = Termisu::Terminfo::Builtin.keys_for("linux")

        keys[0].should eq("\e[[A") # F1
        keys[1].should eq("\e[[B") # F2
        keys[2].should eq("\e[[C") # F3
        keys[3].should eq("\e[[D") # F4
        keys[4].should eq("\e[[E") # F5
      end

      it "has different Home/End sequences than xterm" do
        keys = Termisu::Terminfo::Builtin.keys_for("linux")

        keys[14].should eq("\e[1~") # Home
        keys[15].should eq("\e[4~") # End
      end

      it "has same arrow keys as xterm" do
        xterm_keys = Termisu::Terminfo::Builtin.keys_for("xterm")
        linux_keys = Termisu::Terminfo::Builtin.keys_for("linux")

        linux_keys[18..21].should eq(xterm_keys[18..21])
      end
    end

    context "terminal detection" do
      it "detects linux terminal variants" do
        Termisu::Terminfo::Builtin.keys_for("linux-16color").size.should eq(22)
        Termisu::Terminfo::Builtin.keys_for("linux-vt").size.should eq(22)
      end

      it "treats unknown terminals as xterm" do
        keys = Termisu::Terminfo::Builtin.keys_for("unknown-term")
        xterm_keys = Termisu::Terminfo::Builtin.keys_for("xterm")
        keys.should eq(xterm_keys)
      end

      it "treats empty terminal name as xterm" do
        keys = Termisu::Terminfo::Builtin.keys_for("")
        xterm_keys = Termisu::Terminfo::Builtin.keys_for("xterm")
        keys.should eq(xterm_keys)
      end
    end
  end

  describe "consistency checks" do
    it "returns same size arrays for both xterm and linux funcs" do
      xterm = Termisu::Terminfo::Builtin.funcs_for("xterm")
      linux = Termisu::Terminfo::Builtin.funcs_for("linux")
      xterm.size.should eq(linux.size)
    end

    it "returns same size arrays for both xterm and linux keys" do
      xterm = Termisu::Terminfo::Builtin.keys_for("xterm")
      linux = Termisu::Terminfo::Builtin.keys_for("linux")
      xterm.size.should eq(linux.size)
    end

    it "all function sequences are strings" do
      funcs = Termisu::Terminfo::Builtin.funcs_for("xterm")
      funcs.each do |func|
        func.should be_a(String)
      end
    end

    it "all key sequences are strings" do
      keys = Termisu::Terminfo::Builtin.keys_for("xterm")
      keys.each do |key|
        key.should be_a(String)
      end
    end
  end
end
