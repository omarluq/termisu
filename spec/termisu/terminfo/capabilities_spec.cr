require "../../spec_helper"

describe Termisu::Terminfo::Capabilities do
  describe "STRING_CAPS" do
    it "matches the ncurses standard string capability count" do
      Termisu::Terminfo::Capabilities::STRING_CAPS.size.should eq(414)
    end

    it "keeps authoritative term.h sentinel indices" do
      caps = Termisu::Terminfo::Capabilities::STRING_CAPS

      caps.index("cbt").should eq(0)
      caps.index("kref").should eq(178)
      caps.index("krfr").should eq(179)
      caps.index("krpl").should eq(180)
      caps.index("rfi").should eq(215)
      caps.index("setaf").should eq(359)
      caps.index("setab").should eq(360)
      caps.index("sgr1").should eq(392)
      caps.index("OTbc").should eq(397)
      caps.index("box1").should eq(413)
    end
  end
end
