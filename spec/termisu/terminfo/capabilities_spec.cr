require "../../spec_helper"

describe Termisu::Terminfo::Capabilities do
  describe "FUNCS_INDICES" do
    it "is an array of Int16" do
      Termisu::Terminfo::Capabilities::FUNCS_INDICES.should be_a(Array(Int16))
    end

    it "has exactly 12 function indices" do
      Termisu::Terminfo::Capabilities::FUNCS_INDICES.size.should eq(12)
    end

    it "contains the correct indices for terminal capabilities" do
      indices = Termisu::Terminfo::Capabilities::FUNCS_INDICES

      indices[0].should eq(28)  # enter_ca (smcup)
      indices[1].should eq(40)  # exit_ca (rmcup)
      indices[2].should eq(16)  # show_cursor (cnorm)
      indices[3].should eq(13)  # hide_cursor (civis)
      indices[4].should eq(5)   # clear_screen (clear)
      indices[5].should eq(39)  # sgr0 (sgr0)
      indices[6].should eq(36)  # underline (smul)
      indices[7].should eq(27)  # bold (bold)
      indices[8].should eq(26)  # blink (blink)
      indices[9].should eq(30)  # reverse (rev)
      indices[10].should eq(89) # enter_keypad (smkx)
      indices[11].should eq(88) # exit_keypad (rmkx)
    end

    it "all indices are positive" do
      Termisu::Terminfo::Capabilities::FUNCS_INDICES.each do |index|
        index.should be > 0
      end
    end

    it "all indices are unique" do
      indices = Termisu::Terminfo::Capabilities::FUNCS_INDICES
      indices.uniq.size.should eq(indices.size)
    end

    it "indices are in expected terminfo range" do
      Termisu::Terminfo::Capabilities::FUNCS_INDICES.each do |index|
        index.should be < 400 # Reasonable upper bound for terminfo indices
      end
    end
  end

  describe "KEYS_INDICES" do
    it "is an array of Int16" do
      Termisu::Terminfo::Capabilities::KEYS_INDICES.should be_a(Array(Int16))
    end

    it "has exactly 22 key indices" do
      Termisu::Terminfo::Capabilities::KEYS_INDICES.size.should eq(22)
    end

    it "contains the expected key indices" do
      indices = Termisu::Terminfo::Capabilities::KEYS_INDICES

      # Sample of known indices
      indices[0].should eq(66) # F1
      indices[1].should eq(68) # F2
      indices[2].should eq(69) # F3
      indices[3].should eq(70) # F4
    end

    it "all indices are positive" do
      Termisu::Terminfo::Capabilities::KEYS_INDICES.each do |index|
        index.should be > 0
      end
    end

    it "all indices are unique" do
      indices = Termisu::Terminfo::Capabilities::KEYS_INDICES
      indices.uniq.size.should eq(indices.size)
    end

    it "indices are in expected terminfo key range" do
      Termisu::Terminfo::Capabilities::KEYS_INDICES.each do |index|
        index.should be < 500 # Reasonable upper bound for key indices
      end
    end
  end

  describe "constants are accessible" do
    it "FUNCS_INDICES is accessible" do
      Termisu::Terminfo::Capabilities::FUNCS_INDICES.should be_a(Array(Int16))
    end

    it "KEYS_INDICES is accessible" do
      Termisu::Terminfo::Capabilities::KEYS_INDICES.should be_a(Array(Int16))
    end
  end

  describe "index mapping consistency" do
    it "has matching sizes with Builtin funcs" do
      funcs = Termisu::Terminfo::Builtin.funcs_for("xterm")
      Termisu::Terminfo::Capabilities::FUNCS_INDICES.size.should eq(funcs.size)
    end

    it "has matching sizes with Builtin keys" do
      keys = Termisu::Terminfo::Builtin.keys_for("xterm")
      Termisu::Terminfo::Capabilities::KEYS_INDICES.size.should eq(keys.size)
    end
  end

  describe "terminfo capability mappings" do
    it "enter_ca index is for smcup capability" do
      Termisu::Terminfo::Capabilities::FUNCS_INDICES[0].should eq(28)
    end

    it "exit_ca index is for rmcup capability" do
      Termisu::Terminfo::Capabilities::FUNCS_INDICES[1].should eq(40)
    end

    it "clear_screen index is for clear capability" do
      Termisu::Terminfo::Capabilities::FUNCS_INDICES[4].should eq(5)
    end

    it "sgr0 index is for reset attributes capability" do
      Termisu::Terminfo::Capabilities::FUNCS_INDICES[5].should eq(39)
    end
  end
end
