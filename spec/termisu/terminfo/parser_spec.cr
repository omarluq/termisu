require "../../spec_helper"

# Reference decode mirroring the pre-optimization parse-all-then-filter
# algorithm: reads every string capability, then filters to the requested
# names. Used to prove the required-only fast path is byte-identical.
private def reference_parse_all_then_filter(data : Bytes, requested : Array(String)) : Hash(String, String)
  io = IO::Memory.new(data)
  header = StaticArray(Int16, 6).new { io.read_bytes(Int16, IO::ByteFormat::LittleEndian) }
  names_len = header[1].to_i32
  bools_len = header[2].to_i32
  nums_len = header[3].to_i32
  str_count = header[4].to_i32
  number_size = header[0] == Termisu::Terminfo::Parser::EXTENDED_MAGIC ? 4 : 2
  bools_len += 1 if (names_len + bools_len).odd?
  str_offset = Termisu::Terminfo::Parser::HEADER_LENGTH + names_len + bools_len + (number_size * nums_len)
  table_offset = str_offset + (2 * str_count)

  all = {} of Int32 => String
  str_count.times do |index|
    io.pos = str_offset + (2 * index)
    offset = io.read_bytes(Int16, IO::ByteFormat::LittleEndian)
    next if offset < 0
    io.pos = table_offset + offset
    value = String.build do |builder|
      while (byte = io.read_byte) && byte != 0
        builder.write_byte(byte)
      end
    end
    all[index] = value unless value.empty?
  end

  result = {} of String => String
  requested.each do |name|
    if index = Termisu::Terminfo::Capabilities.string_cap_index(name)
      result[name] = all[index] if all.has_key?(index)
    end
  end
  result
end

private def bounded_terminfo_fixture(
  clear_offset : Int16,
  table : Bytes,
  *,
  trailing : Bytes = Bytes.new(0),
  magic : Int16 = Termisu::Terminfo::Parser::MAGIC,
) : Bytes
  io = IO::Memory.new
  io.write_bytes(magic, IO::ByteFormat::LittleEndian)
  io.write_bytes(0_i16, IO::ByteFormat::LittleEndian)             # names length
  io.write_bytes(0_i16, IO::ByteFormat::LittleEndian)             # boolean count
  io.write_bytes(0_i16, IO::ByteFormat::LittleEndian)             # number count
  io.write_bytes(6_i16, IO::ByteFormat::LittleEndian)             # through clear (index 5)
  io.write_bytes(table.size.to_i16, IO::ByteFormat::LittleEndian) # string table size
  5.times { io.write_bytes(-1_i16, IO::ByteFormat::LittleEndian) }
  io.write_bytes(clear_offset, IO::ByteFormat::LittleEndian)
  io.write(table)
  io.write(trailing)
  io.to_slice
end

private def infocmp_available?(terminal : String) : Bool
  Termisu::Terminfo::Database.new(terminal).load
  Process.run("infocmp", ["-1", terminal], output: IO::Memory.new, error: IO::Memory.new).success?
rescue
  false
end

private def infocmp_strings(terminal : String, requested : Array(String)) : Hash(String, String)
  output = IO::Memory.new
  status = Process.run("infocmp", ["-1", terminal], output: output, error: IO::Memory.new)
  raise "infocmp failed for #{terminal}" unless status.success?

  result = {} of String => String
  output.to_s.each_line do |line|
    entry = line.strip
    separator = entry.index('=')
    next unless separator && entry.ends_with?(',')

    name = entry[0, separator]
    next unless requested.includes?(name)

    encoded = entry[separator + 1, entry.size - separator - 2]
    result[name] = decode_infocmp_string(encoded)
  end
  result
end

private def decode_infocmp_string(encoded : String) : String
  source = encoded.to_slice
  output = IO::Memory.new
  index = 0

  while index < source.size
    byte = source[index]
    if byte == '\\'.ord
      index = write_infocmp_escape(output, source, index + 1)
    elsif byte == '^'.ord && index + 1 < source.size
      control = source[index + 1]
      output.write_byte(control == '?'.ord ? 0x7f_u8 : (control & 0x1f).to_u8)
      index += 2
    else
      output.write_byte(byte)
      index += 1
    end
  end

  output.to_s
end

private def write_infocmp_escape(output : IO, source : Bytes, index : Int32) : Int32
  return index if index == source.size

  byte = source[index]
  return write_infocmp_octal(output, source, index) if byte >= '0'.ord && byte <= '7'.ord

  output.write_byte decoded_infocmp_escape_byte(byte)
  index + 1
end

private def write_infocmp_octal(output : IO, source : Bytes, index : Int32) : Int32
  value = 0
  digits = 0
  while digits < 3 && index < source.size && source[index] >= '0'.ord && source[index] <= '7'.ord
    value = (value * 8) + source[index] - '0'.ord
    index += 1
    digits += 1
  end
  output.write_byte(value.to_u8)
  index
end

private def decoded_infocmp_escape_byte(byte : UInt8) : UInt8
  case byte
  when 'E'.ord, 'e'.ord then 0x1b_u8
  when 'a'.ord          then 0x07_u8
  when 'b'.ord          then 0x08_u8
  when 'f'.ord          then 0x0c_u8
  when 'n'.ord, 'l'.ord then 0x0a_u8
  when 'r'.ord          then 0x0d_u8
  when 's'.ord          then 0x20_u8
  when 't'.ord          then 0x09_u8
  else                       byte
  end
end

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

  describe "bounded string table" do
    it "raises InvalidOffset when a requested offset points into trailing data" do
      data = bounded_terminfo_fixture(1_i16, Bytes[0_u8], trailing: "outside\0".to_slice)

      error = expect_raises(Termisu::ParseError) do
        Termisu::Terminfo::Parser.parse(data, ["clear"])
      end

      error.type.should eq(Termisu::ParseError::Type::InvalidOffset)
      error.details.should eq("Offset out of bounds")
    end

    it "raises CorruptedString rather than scanning for a terminator in trailing data" do
      data = bounded_terminfo_fixture(0_i16, "inside".to_slice, trailing: Bytes[0_u8])

      error = expect_raises(Termisu::ParseError) do
        Termisu::Terminfo::Parser.parse(data, ["clear"])
      end

      error.type.should eq(Termisu::ParseError::Type::CorruptedString)
      error.details.should eq("String crosses the declared table boundary")
    end

    it "raises TruncatedData when the declared table extends past the input" do
      data = bounded_terminfo_fixture(0_i16, "x\0".to_slice)
      data[10] = 20_u8 # table size, little-endian

      error = expect_raises(Termisu::ParseError) do
        Termisu::Terminfo::Parser.parse(data, ["clear"])
      end

      error.type.should eq(Termisu::ParseError::Type::TruncatedData)
    end

    it "accepts trailing extended-section data without reading it as standard data" do
      data = bounded_terminfo_fixture(
        0_i16,
        "value\0".to_slice,
        trailing: Bytes[0xff_u8, 0xff_u8, 0xff_u8],
        magic: Termisu::Terminfo::Parser::EXTENDED_MAGIC
      )

      Termisu::Terminfo::Parser.parse(data, ["clear"]).should eq({"clear" => "value"})
    end

    it "validates malformed offsets only for requested capabilities" do
      data = bounded_terminfo_fixture(1_i16, Bytes[0_u8], trailing: "outside\0".to_slice)

      Termisu::Terminfo::Parser.parse(data, ["cbt"]).should be_empty
    end
  end

  describe "requested capability behavior" do
    it "ignores duplicate and unknown requests without duplicating results" do
      data = bounded_terminfo_fixture(0_i16, "value\0".to_slice)

      result = Termisu::Terminfo::Parser.parse(data, ["unknown", "clear", "clear", "other"])

      result.should eq({"clear" => "value"})
    end

    it "omits absent and cancelled negative offsets" do
      [-1_i16, -2_i16].each do |offset|
        data = bounded_terminfo_fixture(offset, "unused\0".to_slice)
        Termisu::Terminfo::Parser.parse(data, ["clear"]).should be_empty
      end
    end

    it "preserves the existing omission of empty capability strings" do
      data = bounded_terminfo_fixture(0_i16, Bytes[0_u8])

      Termisu::Terminfo::Parser.parse(data, ["clear"]).should be_empty
    end

    it "returns exact owned strings that do not alias the input bytes" do
      data = bounded_terminfo_fixture(0_i16, "value\0".to_slice)
      value = Termisu::Terminfo::Parser.parse(data, ["clear"])["clear"]
      table_start = Termisu::Terminfo::Parser::HEADER_LENGTH + (6 * 2)

      data[table_start] = 'X'.ord.to_u8
      value.should eq("value")
      value.bytesize.should eq(5)
    end

    it "reads little-endian fields safely from an unaligned Bytes slice" do
      data = bounded_terminfo_fixture(0_i16, "value\0".to_slice)
      storage = Bytes.new(data.size + 1, 0_u8)
      unaligned = storage[1, data.size]
      unaligned.copy_from(data)

      Termisu::Terminfo::Parser.parse(unaligned, ["clear"]).should eq({"clear" => "value"})
    end
  end

  describe "error details" do
    it "preserves the named arguments for InvalidOffset errors" do
      error = Termisu::ParseError.invalid_offset(offset: 1, max: 2)

      error.type.should eq(Termisu::ParseError::Type::InvalidOffset)
    end

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
    if TerminfoHelpers.terminfo_db_available?("xterm-256color")
      it "can parse actual xterm-256color terminfo if available" do
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
      end
    else
      pending "real xterm-256color terminfo parsing (no xterm-256color terminfo on this system)"
    end

    if TerminfoHelpers.terminfo_db_available?("xterm-256color")
      it "correctly parses smcup/rmcup for xterm-256color" do
        db = Termisu::Terminfo::Database.new("xterm-256color")
        data = db.load

        result = Termisu::Terminfo::Parser.parse(data, ["smcup", "rmcup"])

        result["smcup"]?.should_not be_nil
        result["rmcup"]?.should_not be_nil
        result["smcup"].should contain("\e[?1049")
        result["rmcup"].should contain("\e[?1049")
      end
    else
      pending "smcup/rmcup parsing for xterm-256color (no xterm-256color terminfo on this system)"
    end
  end

  describe "required-only decode" do
    if TerminfoHelpers.terminfo_db_available?("xterm-256color")
      it "is byte-identical to a full parse-all-then-filter decode for xterm-256color" do
        data = Termisu::Terminfo::Database.new("xterm-256color").load
        required = Termisu::Terminfo::Capabilities::REQUIRED_FUNCS +
                   Termisu::Terminfo::Capabilities::REQUIRED_KEYS

        fast = Termisu::Terminfo::Parser.parse(data, required)
        reference = reference_parse_all_then_filter(data, required)

        fast.size.should be > 0
        fast.keys.should eq(reference.keys)
        reference.each do |name, value|
          fast[name].to_slice.should eq(value.to_slice)
        end
      end
    else
      pending "byte-identical required-only decode (no xterm-256color terminfo on this system)"
    end

    it "matches the reference decode on mock terminfo data" do
      data = create_mock_terminfo_data
      requested = ["clear", "cnorm", "civis", "bold", "smul"]

      fast = Termisu::Terminfo::Parser.parse(data, requested)
      reference = reference_parse_all_then_filter(data, requested)

      fast.should eq(reference)
    end
  end

  describe "infocmp differential" do
    ["xterm", "xterm-256color", "linux", "screen", "tmux"].each do |terminal|
      if infocmp_available?(terminal)
        it "matches infocmp for installed #{terminal}" do
          requested = ["clear", "bold", "cup", "smcup", "rmcup"]
          data = Termisu::Terminfo::Database.new(terminal).load
          expected = infocmp_strings(terminal, requested)
          actual = Termisu::Terminfo::Parser.parse(data, requested)

          expected.should_not be_empty
          actual.should eq(expected)
        end
      else
        pending "infocmp differential for #{terminal} (entry or infocmp unavailable)"
      end
    end
  end

  describe "integration with Capabilities" do
    if TerminfoHelpers.terminfo_db_available?("xterm")
      it "can parse all REQUIRED_FUNCS capabilities" do
        db = Termisu::Terminfo::Database.new("xterm")
        data = db.load

        result = Termisu::Terminfo::Parser.parse(data, Termisu::Terminfo::Capabilities::REQUIRED_FUNCS)

        result.should be_a(Hash(String, String))
        result.size.should be > 0
      end
    else
      pending "REQUIRED_FUNCS parsing (no xterm terminfo on this system)"
    end

    if TerminfoHelpers.terminfo_db_available?("xterm")
      it "can parse all REQUIRED_KEYS capabilities" do
        db = Termisu::Terminfo::Database.new("xterm")
        data = db.load

        result = Termisu::Terminfo::Parser.parse(data, Termisu::Terminfo::Capabilities::REQUIRED_KEYS)

        result.should be_a(Hash(String, String))
        result.size.should be > 0
      end
    else
      pending "REQUIRED_KEYS parsing (no xterm terminfo on this system)"
    end
  end

  describe "extended format handling" do
    # Gated on the host entry actually being extended, not just present. The magic
    # check used to sit inside the example around its assertions, so on a machine
    # whose xterm-256color is standard-format the example ran to completion having
    # asserted nothing and still reported as a pass.
    if TerminfoHelpers.terminfo_db_extended?("xterm-256color")
      it "correctly handles extended 32-bit format" do
        data = Termisu::Terminfo::Database.new("xterm-256color").load

        result = Termisu::Terminfo::Parser.new(data).parse(["clear", "bold"])

        result.should be_a(Hash(String, String))
        result.size.should be > 0
      end
    else
      pending "extended 32-bit format handling (no extended-format xterm-256color entry here)"
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
