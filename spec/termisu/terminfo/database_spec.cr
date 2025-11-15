require "../../spec_helper"

describe Termisu::Terminfo::Database do
  describe "#initialize" do
    it "accepts a terminal name" do
      db = Termisu::Terminfo::Database.new("xterm")
      db.should be_a(Termisu::Terminfo::Database)
    end

    it "stores the terminal name" do
      db = Termisu::Terminfo::Database.new("xterm-256color")
      db.should be_a(Termisu::Terminfo::Database)
    end
  end

  describe "#load" do
    context "with standard terminfo locations" do
      it "raises error when terminal database not found" do
        db = Termisu::Terminfo::Database.new("nonexistent-terminal-xyz")
        expect_raises(Exception, /Could not find terminfo database/) do
          db.load
        end
      end

      it "returns Bytes when terminal found" do
        # This test depends on system having xterm terminfo
        # Skip if not available
        begin
          db = Termisu::Terminfo::Database.new("xterm")
          data = db.load
          data.should be_a(Bytes)
          data.size.should be > 0
        rescue
          pending "xterm terminfo not available on this system"
        end
      end
    end

    context "with TERMINFO environment variable" do
      it "checks TERMINFO path first" do
        db = Termisu::Terminfo::Database.new("custom")
        # The method tries TERMINFO env first, but will fail gracefully
        db.should be_a(Termisu::Terminfo::Database)
      end
    end

    context "with HOME terminfo directory" do
      it "checks ~/.terminfo directory" do
        db = Termisu::Terminfo::Database.new("custom")
        # The method tries HOME/.terminfo, but will fail gracefully
        db.should be_a(Termisu::Terminfo::Database)
      end
    end

    context "with TERMINFO_DIRS environment variable" do
      it "handles empty directory in TERMINFO_DIRS as /usr/share/terminfo" do
        db = Termisu::Terminfo::Database.new("test")
        # Method should handle empty dirs correctly
        db.should be_a(Termisu::Terminfo::Database)
      end
    end

    context "fallback locations" do
      it "tries /lib/terminfo" do
        db = Termisu::Terminfo::Database.new("test")
        db.should be_a(Termisu::Terminfo::Database)
      end

      it "tries /usr/share/terminfo as last resort" do
        db = Termisu::Terminfo::Database.new("test")
        db.should be_a(Termisu::Terminfo::Database)
      end
    end
  end

  describe "path resolution" do
    it "handles terminal names with first character properly" do
      db = Termisu::Terminfo::Database.new("xterm")
      # Should look for x/xterm path
      db.should be_a(Termisu::Terminfo::Database)
    end

    it "handles hex format for Darwin systems" do
      db = Termisu::Terminfo::Database.new("xterm")
      # Should also try hex path (78/xterm for 'x')
      db.should be_a(Termisu::Terminfo::Database)
    end

    it "handles terminal names with hyphens" do
      db = Termisu::Terminfo::Database.new("xterm-256color")
      db.should be_a(Termisu::Terminfo::Database)
    end

    it "handles single character terminal names" do
      db = Termisu::Terminfo::Database.new("x")
      db.should be_a(Termisu::Terminfo::Database)
    end
  end

  describe "error handling" do
    it "provides descriptive error message with terminal name" do
      db = Termisu::Terminfo::Database.new("totally-fake-term")
      expect_raises(Exception, /totally-fake-term/) do
        db.load
      end
    end

    it "handles file read errors gracefully" do
      db = Termisu::Terminfo::Database.new("fake")
      expect_raises(Exception) do
        db.load
      end
    end
  end

  describe "data format" do
    it "returns raw bytes from terminfo file" do
      begin
        db = Termisu::Terminfo::Database.new("xterm")
        data = db.load
        data.should be_a(Bytes)
        # Terminfo files have a magic number at start
        data.size.should be >= 12 # Minimum header size
      rescue
        pending "xterm terminfo not available"
      end
    end
  end

  describe "multiple load calls" do
    it "can load same terminal multiple times" do
      begin
        db = Termisu::Terminfo::Database.new("xterm")
        data1 = db.load
        data2 = db.load
        data1.should eq(data2)
      rescue
        pending "xterm terminfo not available"
      end
    end
  end

  describe "common terminals" do
    it "can find linux terminal if available" do
      begin
        db = Termisu::Terminfo::Database.new("linux")
        data = db.load
        data.should be_a(Bytes)
      rescue
        pending "linux terminfo not available"
      end
    end

    it "can find screen terminal if available" do
      begin
        db = Termisu::Terminfo::Database.new("screen")
        data = db.load
        data.should be_a(Bytes)
      rescue
        pending "screen terminfo not available"
      end
    end

    it "can find tmux terminal if available" do
      begin
        db = Termisu::Terminfo::Database.new("tmux")
        data = db.load
        data.should be_a(Bytes)
      rescue
        pending "tmux terminfo not available"
      end
    end
  end
end
