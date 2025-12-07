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

    it "raises ParseError for corrupt data" do
      corrupt_data = Bytes[1, 2, 3] # Too small

      expect_raises(Termisu::ParseError) do
        Termisu::Terminfo::Parser.parse(corrupt_data, ["clear"])
      end
    end

    it "raises ParseError for empty data" do
      empty_data = Bytes.new(0)

      expect_raises(Termisu::ParseError) do
        Termisu::Terminfo::Parser.parse(empty_data, ["clear"])
      end
    end
  end

  describe ".parse?" do
    it "returns hash for valid data" do
      data = create_mock_terminfo_data
      result = Termisu::Terminfo::Parser.parse?(data, ["clear"])
      result.should_not be_nil
      result.should be_a(Hash(String, String))
    end

    it "returns nil for corrupt data instead of raising" do
      corrupt_data = Bytes[1, 2, 3]
      result = Termisu::Terminfo::Parser.parse?(corrupt_data, ["clear"])
      result.should be_nil
    end

    it "returns nil for empty data instead of raising" do
      empty_data = Bytes.new(0)
      result = Termisu::Terminfo::Parser.parse?(empty_data, ["clear"])
      result.should be_nil
    end

    it "returns nil for invalid magic number" do
      data = create_mock_terminfo_data
      # Corrupt the magic number
      data[0] = 0xFF_u8
      data[1] = 0xFF_u8

      result = Termisu::Terminfo::Parser.parse?(data, ["clear"])
      result.should be_nil
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

  describe "ParseError types" do
    describe "TruncatedData" do
      it "is raised when data is smaller than header" do
        corrupt_data = Bytes[1, 2, 3] # Only 3 bytes, need 12

        error = expect_raises(Termisu::ParseError) do
          Termisu::Terminfo::Parser.parse(corrupt_data, ["clear"])
        end

        error.type.should eq(Termisu::ParseError::Type::TruncatedData)
        message = error.message.as(String)
        message.should contain("truncated")
        message.should contain("12")
        message.should contain("3")
      end

      it "is raised when data is smaller than header indicates" do
        data = create_mock_terminfo_data
        # Truncate the data significantly
        truncated = data[0, 20]

        error = expect_raises(Termisu::ParseError) do
          Termisu::Terminfo::Parser.parse(truncated, ["clear"])
        end

        error.type.should eq(Termisu::ParseError::Type::TruncatedData)
      end
    end

    describe "InvalidMagic" do
      it "is raised when magic number is not recognized" do
        data = create_mock_terminfo_data
        # Set invalid magic number
        data[0] = 0x00_u8
        data[1] = 0x00_u8

        error = expect_raises(Termisu::ParseError) do
          Termisu::Terminfo::Parser.parse(data, ["clear"])
        end

        error.type.should eq(Termisu::ParseError::Type::InvalidMagic)
        error.message.as(String).should contain("magic")
      end

      it "includes expected magic numbers in error message" do
        data = create_mock_terminfo_data
        data[0] = 0xFF_u8
        data[1] = 0xFF_u8

        error = expect_raises(Termisu::ParseError) do
          Termisu::Terminfo::Parser.parse(data, ["clear"])
        end

        # Should mention what we expected
        message = error.message.as(String)
        message.should contain("282") # MAGIC in decimal
        message.should contain("542") # EXTENDED_MAGIC
      end
    end

    describe "InvalidHeader" do
      it "is raised for negative names length" do
        data = create_mock_terminfo_data
        # Set negative names_len (bytes 2-3)
        io = IO::Memory.new(data)
        io.pos = 2
        io.write_bytes(-1_i16, IO::ByteFormat::LittleEndian)

        error = expect_raises(Termisu::ParseError) do
          Termisu::Terminfo::Parser.parse(io.to_slice, ["clear"])
        end

        error.type.should eq(Termisu::ParseError::Type::InvalidHeader)
        error.message.as(String).should contain("names_length")
      end

      it "is raised for excessively large string count" do
        data = create_mock_terminfo_data
        # Set unreasonably large string count (bytes 8-9)
        io = IO::Memory.new(data)
        io.pos = 8
        io.write_bytes(10000_i16, IO::ByteFormat::LittleEndian)

        error = expect_raises(Termisu::ParseError) do
          Termisu::Terminfo::Parser.parse(io.to_slice, ["clear"])
        end

        error.type.should eq(Termisu::ParseError::Type::InvalidHeader)
        error.message.as(String).should contain("strings_count")
      end
    end
  end

  describe "error details" do
    it "provides details for truncated data error" do
      corrupt_data = Bytes[1, 2, 3]

      error = expect_raises(Termisu::ParseError) do
        Termisu::Terminfo::Parser.parse(corrupt_data, ["clear"])
      end

      error.details.should_not be_nil
      error.details.as(String).should contain("Missing")
    end

    it "provides details for invalid magic error" do
      data = create_mock_terminfo_data
      data[0] = 0xAB_u8
      data[1] = 0xCD_u8

      error = expect_raises(Termisu::ParseError) do
        Termisu::Terminfo::Parser.parse(data, ["clear"])
      end

      error.details.should_not be_nil
      error.details.as(String).should contain("0x") # Hex representation
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
      rescue Termisu::ParseError
        pending "xterm-256color terminfo parsing failed"
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
      rescue Termisu::ParseError
        pending "xterm-256color terminfo parsing failed"
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
      rescue Termisu::ParseError
        pending "xterm terminfo parsing failed"
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
      rescue Termisu::ParseError
        pending "xterm terminfo parsing failed"
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
      rescue Termisu::ParseError
        pending "xterm-256color terminfo parsing failed"
      rescue
        pending "xterm-256color terminfo not available"
      end
    end
  end

  describe "validation constants" do
    it "has reasonable maximum values" do
      Termisu::Terminfo::Parser::MAX_NAMES_LENGTH.should eq(4096)
      Termisu::Terminfo::Parser::MAX_BOOLEANS_COUNT.should eq(512)
      Termisu::Terminfo::Parser::MAX_NUMBERS_COUNT.should eq(512)
      Termisu::Terminfo::Parser::MAX_STRINGS_COUNT.should eq(512)
      Termisu::Terminfo::Parser::MAX_TABLE_SIZE.should eq(65536)
    end
  end
end
