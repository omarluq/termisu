# Binary terminfo database parser.
#
# Parses compiled terminfo database files in the ncurses binary format, supporting
# both standard 16-bit and extended 32-bit formats. The parser uses name-based
# capability lookup via the Capabilities::STRING_CAPS ordering to map capability
# names to their escape sequences.
#
# ## Binary Format
#
# The terminfo binary format consists of:
# - Header (12 bytes): Magic number and section sizes
# - Names section: Terminal names (pipe-separated)
# - Booleans section: Boolean capabilities (1 byte each)
# - Numbers section: Numeric capabilities (2 or 4 bytes each)
# - Strings section: String capability offsets (2 bytes each)
# - String table: Null-terminated string data
#
# ## Format Detection
#
# - Magic 0o432 (282): Standard format with 16-bit numbers
# - Magic 542: Extended format with 32-bit numbers
#
# ## Error Handling
#
# The parser raises `ParseError` with specific error types:
# - `InvalidMagic`: Unrecognized format identifier
# - `TruncatedData`: File smaller than header indicates
# - `InvalidHeader`: Negative or unreasonable header values
# - `InvalidOffset`: String offsets point outside data bounds
#
# ## Usage
#
# ```
# data = File.read("/usr/share/terminfo/x/xterm-256color")
# caps = Parser.parse(data, ["clear", "bold", "smcup"])
# # Raises ParseError if data is malformed
# ```
class Termisu::Terminfo::Parser
  # Magic number for standard 16-bit terminfo format.
  MAGIC = 0o432_i16

  # Magic number for extended 32-bit terminfo format.
  EXTENDED_MAGIC = 542_i16

  # Size of terminfo binary header in bytes.
  HEADER_LENGTH = 12

  # Maximum reasonable header values to detect corruption.
  MAX_NAMES_LENGTH   =  4096
  MAX_BOOLEANS_COUNT =   512
  MAX_NUMBERS_COUNT  =   512
  MAX_STRINGS_COUNT  =   512
  MAX_TABLE_SIZE     = 65536

  # Parses terminfo binary data and returns requested capabilities.
  #
  # Creates a new parser instance and extracts the specified capabilities
  # from the terminfo database.
  #
  # ## Parameters
  #
  # - `data`: Raw terminfo binary data
  # - `cap_names`: Array of capability names to extract (e.g., ["clear", "bold"])
  #
  # ## Returns
  #
  # Hash mapping capability names to their escape sequence values.
  #
  # ## Raises
  #
  # - `ParseError` if the data is malformed or corrupted
  def self.parse(data : Bytes, cap_names : Array(String)) : Hash(String, String)
    new(data).parse(cap_names)
  end

  # Parses terminfo data, returning nil on parse errors instead of raising.
  #
  # Useful when you want to handle parse failures gracefully without exceptions.
  #
  # ## Returns
  #
  # Hash of capabilities, or nil if parsing failed.
  def self.parse?(data : Bytes, cap_names : Array(String)) : Hash(String, String)?
    parse(data, cap_names)
  rescue ParseError
    nil
  end

  def initialize(@data : Bytes)
  end

  # Parses capability values from terminfo binary data.
  #
  # Reads the binary format, extracts all string capabilities, then filters
  # to only the requested capability names using STRING_CAPS ordering.
  #
  # ## Parameters
  #
  # - `required_caps`: Capability names to extract
  #
  # ## Returns
  #
  # Hash of capability name => escape sequence. Missing capabilities are omitted.
  #
  # ## Raises
  #
  # - `ParseError` with specific type on malformed data
  def parse(required_caps : Array(String)) : Hash(String, String)
    validate_minimum_size!

    io = IO::Memory.new(@data)

    header = read_header(io)
    validate_header!(header)

    offsets = calculate_offsets(header)
    validate_offsets!(offsets, header)

    string_count = header[4]

    # Parse all string capabilities from binary format
    all_capabilities = parse_all_strings(io, string_count, offsets)

    # Filter to only requested capabilities
    extract_requested_capabilities(all_capabilities, required_caps)
  end

  # Validates that data is at least large enough for the header.
  private def validate_minimum_size!
    if @data.size < HEADER_LENGTH
      raise ParseError.truncated_data(HEADER_LENGTH, @data.size)
    end
  end

  # Validates the header magic number and field values.
  private def validate_header!(header : StaticArray(Int16, 6))
    validate_magic!(header[0])
    validate_header_field!("names_length", header[1], MAX_NAMES_LENGTH)
    validate_header_field!("booleans_count", header[2], MAX_BOOLEANS_COUNT)
    validate_header_field!("numbers_count", header[3], MAX_NUMBERS_COUNT)
    validate_header_field!("strings_count", header[4], MAX_STRINGS_COUNT)
    validate_header_field!("table_size", header[5], MAX_TABLE_SIZE)
  end

  # Validates the terminfo magic number.
  private def validate_magic!(magic : Int16)
    unless magic == MAGIC || magic == EXTENDED_MAGIC
      raise ParseError.invalid_magic(magic)
    end
  end

  # Validates a single header field is within valid range.
  private def validate_header_field!(name : String, value : Int16, max : Int32)
    if value < 0 || value > max
      raise ParseError.invalid_header(name, value)
    end
  end

  # Validates that calculated offsets don't exceed data bounds.
  private def validate_offsets!(offsets : NamedTuple, header : StaticArray(Int16, 6))
    table_size = header[5]
    expected_end = offsets[:table_offset].to_i32 + table_size.to_i32

    if expected_end > @data.size
      raise ParseError.truncated_data(expected_end, @data.size)
    end
  end

  # Parses all string capabilities from the terminfo binary data.
  #
  # Reads each string capability offset and extracts the null-terminated
  # string from the string table.
  private def parse_all_strings(io, count, offsets)
    capabilities = {} of Int32 => String

    count.times do |index|
      offset_position = offsets[:str_offset] + (2_i16 * index)
      value = read_string_at(io, offset_position, offsets[:table_offset])
      capabilities[index] = value unless value.empty?
    end

    capabilities
  end

  # Extracts requested capabilities from the parsed capability set.
  #
  # Uses STRING_CAPS ordering to map capability names to their indices,
  # then looks up the corresponding values.
  private def extract_requested_capabilities(all_caps, requested)
    result = {} of String => String

    requested.each do |cap_name|
      if index = Capabilities::STRING_CAPS.index(cap_name)
        result[cap_name] = all_caps[index] if all_caps.has_key?(index)
      end
    end

    result
  end

  # Reads the 12-byte terminfo header.
  #
  # Header structure:
  # - [0]: Magic number (format identifier)
  # - [1]: Names section size
  # - [2]: Boolean capabilities count
  # - [3]: Numeric capabilities count
  # - [4]: String capabilities count
  # - [5]: String table size
  private def read_header(io : IO::Memory)
    StaticArray(Int16, 6).new do |_|
      io.read_bytes(Int16, IO::ByteFormat::LittleEndian)
    end
  end

  # Calculates byte offsets for strings section and string table.
  #
  # The calculation accounts for:
  # - Variable number section size (2 bytes for standard, 4 for extended)
  # - Word boundary alignment for booleans section
  private def calculate_offsets(header)
    magic, names_len, bools_len, nums_len, str_count = header[0], header[1], header[2], header[3], header[4]

    # Extended format uses 32-bit numbers instead of 16-bit
    number_size = (magic == EXTENDED_MAGIC) ? 4_i16 : 2_i16

    # Align booleans section to word boundary
    bools_len += 1_i16 if (names_len + bools_len).odd?

    str_offset = HEADER_LENGTH.to_i16 + names_len + bools_len + (number_size * nums_len)
    table_offset = str_offset + (2_i16 * str_count)

    {str_offset: str_offset, table_offset: table_offset}
  end

  # Reads a null-terminated string at the given offset position.
  #
  # ## Parameters
  #
  # - `io`: Memory IO containing terminfo data
  # - `offset_pos`: Position of the 16-bit offset value
  # - `table_start`: Start position of the string table
  #
  # ## Returns
  #
  # The null-terminated string, or empty string if offset is -1 (absent capability).
  private def read_string_at(io : IO::Memory, offset_pos : Int16, table_start : Int16) : String
    io.pos = offset_pos.to_i
    offset = io.read_bytes(Int16, IO::ByteFormat::LittleEndian)

    # -1 offset means capability is absent (not an error)
    return "" if offset < 0

    string_pos = (table_start + offset).to_i

    # Validate the string position is within bounds
    if string_pos >= @data.size
      raise ParseError.invalid_offset(string_pos, @data.size)
    end

    io.pos = string_pos
    read_null_terminated_string(io)
  end

  # Reads a null-terminated string from the current IO position.
  private def read_null_terminated_string(io : IO::Memory) : String
    bytes = [] of UInt8

    loop do
      byte = io.read_byte
      break if byte.nil? || byte.zero?
      bytes << byte
    end

    String.new(Slice.new(bytes.to_unsafe, bytes.size))
  end
end
