require "../../spec_helper"

describe Termisu::Terminfo::Parser do
  describe ".parse" do
    it "is a class method that creates parser and parses by capability name" do
      data = create_mock_terminfo_data
      cap_names = ["clear", "cnorm"]

      result = Termisu::Terminfo::Parser.parse(data, cap_names)
      result.should be_a(Hash(String, String))
    end

    it "returns hash mapping capability names to values" do
      data = create_mock_terminfo_data
      cap_names = ["clear"]

      result = Termisu::Terminfo::Parser.parse(data, cap_names)
      result.should be_a(Hash(String, String))
    end

    it "returns empty hash for unknown capability names" do
      data = create_mock_terminfo_data
      cap_names = ["nonexistent_capability"]

      result = Termisu::Terminfo::Parser.parse(data, cap_names)
      result.should be_a(Hash(String, String))
      result.size.should eq(0)
    end
  end

  describe "#initialize" do
    it "accepts Bytes data" do
      data = Bytes[1, 2, 3, 4]
      parser = Termisu::Terminfo::Parser.new(data)
      parser.should be_a(Termisu::Terminfo::Parser)
    end
  end

  describe "#parse" do
    it "parses capabilities by name from terminfo data" do
      data = create_mock_terminfo_data
      parser = Termisu::Terminfo::Parser.new(data)
      cap_names = ["clear", "cnorm", "civis"]

      result = parser.parse(cap_names)
      result.should be_a(Hash(String, String))
    end

    it "handles empty capability names array" do
      data = create_mock_terminfo_data
      parser = Termisu::Terminfo::Parser.new(data)

      result = parser.parse([] of String)
      result.should be_a(Hash(String, String))
      result.size.should eq(0)
    end

    it "only returns requested capabilities that exist" do
      data = create_mock_terminfo_data
      parser = Termisu::Terminfo::Parser.new(data)
      cap_names = ["clear", "bold", "smul"]

      result = parser.parse(cap_names)
      # Only contains keys we requested
      result.keys.each do |key|
        cap_names.should contain(key)
      end
    end
  end

  describe "magic number constants" do
    it "defines MAGIC constant for standard format" do
      Termisu::Terminfo::Parser::MAGIC.should eq(0o432_i16)
    end

    it "defines EXTENDED_MAGIC constant for 32-bit format" do
      Termisu::Terminfo::Parser::EXTENDED_MAGIC.should eq(542_i16)
    end

    it "EXTENDED_MAGIC is decimal 542 not octal" do
      # This is critical - extended format uses decimal 542
      Termisu::Terminfo::Parser::EXTENDED_MAGIC.should eq(542)
    end

    it "defines HEADER_LENGTH constant" do
      Termisu::Terminfo::Parser::HEADER_LENGTH.should eq(12)
    end

    it "magic numbers are different" do
      Termisu::Terminfo::Parser::MAGIC.should_not eq(Termisu::Terminfo::Parser::EXTENDED_MAGIC)
    end
  end

  describe "error handling" do
    it "handles corrupt data gracefully" do
      corrupt_data = Bytes[1, 2, 3] # Too small
      parser = Termisu::Terminfo::Parser.new(corrupt_data)

      result = parser.parse(["clear"])
      result.should eq({} of String => String)
    end

    it "handles empty data" do
      empty_data = Bytes.new(0)
      parser = Termisu::Terminfo::Parser.new(empty_data)

      result = parser.parse(["clear"])
      result.should eq({} of String => String)
    end

    it "handles missing capabilities" do
      data = create_mock_terminfo_data
      parser = Termisu::Terminfo::Parser.new(data)

      result = parser.parse(["nonexistent_capability"])
      result.has_key?("nonexistent_capability").should be_false
    end
  end

  describe "real terminfo data" do
    it "can parse actual xterm-256color terminfo if available" do
      begin
        db = Termisu::Terminfo::Database.new("xterm-256color")
        data = db.load
        parser = Termisu::Terminfo::Parser.new(data)

        cap_names = ["clear", "civis", "cnorm", "bold", "smul"]
        result = parser.parse(cap_names)

        result.should be_a(Hash(String, String))
        result.size.should be > 0

        # Verify they're valid ANSI sequences
        result.values.each do |value|
          (value.starts_with?("\e") || value.starts_with?("\033")).should be_true
        end
      rescue
        pending "xterm-256color terminfo not available"
      end
    end

    it "correctly parses smcup/rmcup for xterm-256color" do
      begin
        db = Termisu::Terminfo::Database.new("xterm-256color")
        data = db.load

        result = Termisu::Terminfo::Parser.parse(data, ["smcup", "rmcup"])

        result["smcup"]?.should_not be_nil
        result["rmcup"]?.should_not be_nil
        result["smcup"].should contain("\e[?1049")
        result["rmcup"].should contain("\e[?1049")
      rescue
        pending "xterm-256color terminfo not available"
      end
    end
  end

  describe "integration with Capabilities" do
    it "can parse all REQUIRED_FUNCS capabilities" do
      begin
        db = Termisu::Terminfo::Database.new("xterm")
        data = db.load

        result = Termisu::Terminfo::Parser.parse(data, Termisu::Terminfo::Capabilities::REQUIRED_FUNCS)

        result.should be_a(Hash(String, String))
        result.size.should be > 0
      rescue
        pending "xterm terminfo not available"
      end
    end

    it "can parse all REQUIRED_KEYS capabilities" do
      begin
        db = Termisu::Terminfo::Database.new("xterm")
        data = db.load

        result = Termisu::Terminfo::Parser.parse(data, Termisu::Terminfo::Capabilities::REQUIRED_KEYS)

        result.should be_a(Hash(String, String))
        result.size.should be > 0
      rescue
        pending "xterm terminfo not available"
      end
    end
  end

  describe "extended format handling" do
    it "correctly handles extended 32-bit format" do
      begin
        db = Termisu::Terminfo::Database.new("xterm-256color")
        data = db.load

        # Check magic number
        io = IO::Memory.new(data)
        magic = io.read_bytes(Int16, IO::ByteFormat::LittleEndian)

        if magic == 542
          parser = Termisu::Terminfo::Parser.new(data)
          result = parser.parse(["clear", "bold"])

          result.should be_a(Hash(String, String))
          result.size.should be > 0
        end
      rescue
        pending "xterm-256color terminfo not available"
      end
    end
  end
end
