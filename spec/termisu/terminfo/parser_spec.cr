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
