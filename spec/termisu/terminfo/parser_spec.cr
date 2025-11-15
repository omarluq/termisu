require "../../spec_helper"

describe Termisu::Terminfo::Parser do
  describe ".parse" do
    it "is a class method that creates parser and parses" do
      # Mock data - minimal valid terminfo header
      data = create_mock_terminfo_data
      indices = [0_i16, 1_i16]

      result = Termisu::Terminfo::Parser.parse(data, indices)
      result.should be_a(Array(String))
    end

    it "returns array of strings" do
      data = create_mock_terminfo_data
      indices = [0_i16]

      result = Termisu::Terminfo::Parser.parse(data, indices)
      result.should be_a(Array(String))
      result.size.should eq(1)
    end

    it "returns empty strings for invalid indices" do
      data = create_mock_terminfo_data
      indices = [999_i16] # Invalid index

      result = Termisu::Terminfo::Parser.parse(data, indices)
      result[0].should eq("")
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
    it "parses indices from terminfo data" do
      data = create_mock_terminfo_data
      parser = Termisu::Terminfo::Parser.new(data)
      indices = [0_i16, 1_i16, 2_i16]

      result = parser.parse(indices)
      result.should be_a(Array(String))
      result.size.should eq(3)
    end

    it "handles empty indices array" do
      data = create_mock_terminfo_data
      parser = Termisu::Terminfo::Parser.new(data)

      result = parser.parse([] of Int16)
      result.should be_a(Array(String))
      result.size.should eq(0)
    end

    it "returns strings for each requested index" do
      data = create_mock_terminfo_data
      parser = Termisu::Terminfo::Parser.new(data)
      indices = [0_i16, 1_i16, 2_i16, 3_i16, 4_i16]

      result = parser.parse(indices)
      result.size.should eq(5)
      result.each do |str|
        str.should be_a(String)
      end
    end
  end

  describe "magic number constants" do
    it "defines MAGIC constant" do
      Termisu::Terminfo::Parser::MAGIC.should eq(0o432_i16)
    end

    it "defines EXTENDED_MAGIC constant" do
      Termisu::Terminfo::Parser::EXTENDED_MAGIC.should eq(0o542_i16)
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

      result = parser.parse([0_i16])
      result[0].should eq("") # Should return empty string on error
    end

    it "handles empty data" do
      empty_data = Bytes.new(0)
      parser = Termisu::Terminfo::Parser.new(empty_data)

      result = parser.parse([0_i16])
      result[0].should eq("")
    end

    it "handles negative indices" do
      data = create_mock_terminfo_data
      parser = Termisu::Terminfo::Parser.new(data)

      result = parser.parse([-1_i16])
      result[0].should eq("")
    end
  end

  describe "real terminfo data" do
    it "can parse actual xterm terminfo if available" do
      begin
        db = Termisu::Terminfo::Database.new("xterm")
        data = db.load
        parser = Termisu::Terminfo::Parser.new(data)

        # Parse a few known capabilities
        indices = [5_i16, 13_i16, 16_i16] # clear, civis, cnorm
        result = parser.parse(indices)

        result.should be_a(Array(String))
        result.size.should eq(3)
        # At least one should be non-empty for xterm
        result.any? { |res| !res.empty? }.should be_true
      rescue
        pending "xterm terminfo not available"
      end
    end
  end

  describe "integration with Capabilities" do
    it "can parse function capabilities indices" do
      begin
        db = Termisu::Terminfo::Database.new("xterm")
        data = db.load

        result = Termisu::Terminfo::Parser.parse(data, Termisu::Terminfo::Capabilities::FUNCS_INDICES)

        result.should be_a(Array(String))
        result.size.should eq(12)
      rescue
        pending "xterm terminfo not available"
      end
    end

    it "can parse key capabilities indices" do
      begin
        db = Termisu::Terminfo::Database.new("xterm")
        data = db.load

        result = Termisu::Terminfo::Parser.parse(data, Termisu::Terminfo::Capabilities::KEYS_INDICES)

        result.should be_a(Array(String))
        result.size.should eq(22)
      rescue
        pending "xterm terminfo not available"
      end
    end
  end

  describe "header parsing" do
    it "handles standard magic number" do
      data = create_mock_terminfo_data(Termisu::Terminfo::Parser::MAGIC)
      parser = Termisu::Terminfo::Parser.new(data)

      result = parser.parse([0_i16])
      result.should be_a(Array(String))
    end

    it "handles extended magic number" do
      data = create_mock_terminfo_data(Termisu::Terminfo::Parser::EXTENDED_MAGIC)
      parser = Termisu::Terminfo::Parser.new(data)

      result = parser.parse([0_i16])
      result.should be_a(Array(String))
    end
  end
end

# Helper method to create minimal valid terminfo data for testing
private def create_mock_terminfo_data(magic = 0o432_i16)
  io = IO::Memory.new

  # Write header (6 Int16 values)
  io.write_bytes(magic, IO::ByteFormat::LittleEndian)   # magic
  io.write_bytes(10_i16, IO::ByteFormat::LittleEndian)  # names section length
  io.write_bytes(0_i16, IO::ByteFormat::LittleEndian)   # boolean section length
  io.write_bytes(5_i16, IO::ByteFormat::LittleEndian)   # numbers section length
  io.write_bytes(10_i16, IO::ByteFormat::LittleEndian)  # string count
  io.write_bytes(100_i16, IO::ByteFormat::LittleEndian) # string table size

  # Write terminal names section (10 bytes)
  io.write("xterm-test".to_slice)

  # Write numbers section (5 * 2 bytes for standard, or 5 * 4 for extended)
  number_size = (magic == 0o542_i16) ? 4 : 2
  5.times do
    if number_size == 4
      io.write_bytes(0_i32, IO::ByteFormat::LittleEndian)
    else
      io.write_bytes(0_i16, IO::ByteFormat::LittleEndian)
    end
  end

  # Write string offset table (10 * 2 bytes)
  10.times do |idx|
    io.write_bytes((idx * 5).to_i16, IO::ByteFormat::LittleEndian)
  end

  # Write string table (10 strings of "test\0")
  10.times do
    io.write("test\0".to_slice)
  end

  io.to_slice
end
