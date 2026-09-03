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
# - `InvalidOffset`: String offsets point outside the declared string table
# - `CorruptedString`: A requested string has no terminator in that table
#
# String offsets and terminator searches are intentionally bounded by the standard
# string table declared in the header. Trailing extended data is accepted, but is
# never interpreted as part of that table. Consequently, malformed files that only
# worked by reading into a trailing section are rejected.
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
  # Resolves each requested capability name to its STRING_CAPS index and
  # decodes only those entries from the strings section, skipping the
  # hundreds of unrequested capabilities a terminfo file typically carries.
  # Structural sections are always validated, but offset or string corruption
  # belonging solely to an unrequested capability is deliberately not observed.
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

    header = read_header
    validate_header!(header)

    offsets = calculate_offsets(header)
    table_end = validate_offsets!(offsets, header)

    string_count = header[4].to_i32
    read_required_capabilities(required_caps, string_count, offsets, table_end)
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

  # Validates that calculated offsets don't exceed data bounds and returns the
  # exclusive end of the declared standard string table. Bytes after that point
  # may hold an extended section and are deliberately not validated here.
  private def validate_offsets!(offsets : NamedTuple, header : StaticArray(Int16, 6)) : Int32
    table_end = offsets[:table_offset] + header[5].to_i32

    if table_end > @data.size
      raise ParseError.truncated_data(table_end, @data.size)
    end

    table_end
  end

  # Decodes only the requested capabilities from the strings section.
  #
  # Maps each requested name to its STRING_CAPS index, reads that entry's
  # 16-bit offset, and extracts the null-terminated string from the string
  # table. Names beyond the file's string count, negative offsets, and empty
  # values are omitted, matching the existing requested-only behavior.
  private def read_required_capabilities(requested, string_count, offsets, table_end)
    capacity = Math.min(requested.size, string_count)
    result = Hash(String, String).new(initial_capacity: capacity)

    requested.each do |cap_name|
      index = Capabilities.string_cap_index(cap_name)
      next unless index && index < string_count

      offset_position = offsets[:str_offset] + (2 * index)
      value = read_string_at(offset_position, offsets[:table_offset], table_end)
      result[cap_name] = value if value && !value.empty?
    end

    result
  end

  # Reads the 12-byte terminfo header with endian-explicit byte operations.
  # This remains safe when the supplied Bytes starts at an unaligned address.
  #
  # Header structure:
  # - [0]: Magic number (format identifier)
  # - [1]: Names section size
  # - [2]: Boolean capabilities count
  # - [3]: Numeric capabilities count
  # - [4]: String capabilities count
  # - [5]: String table size
  private def read_header : StaticArray(Int16, 6)
    StaticArray(Int16, 6).new do |index|
      read_i16_le(index * 2)
    end
  end

  # Calculates byte offsets for strings section and string table.
  #
  # The calculation accounts for:
  # - Variable number section size (2 bytes for standard, 4 for extended)
  # - Word boundary alignment for booleans section
  #
  # Arithmetic is done in Int32: the header fields are Int16, and summing
  # maximum-range sections overflows Int16 on large/extended terminfo files.
  private def calculate_offsets(header)
    magic = header[0]
    names_len = header[1].to_i32
    bools_len = header[2].to_i32
    nums_len = header[3].to_i32
    str_count = header[4].to_i32

    # Extended format uses 32-bit numbers instead of 16-bit
    number_size = (magic == EXTENDED_MAGIC) ? 4 : 2

    # Align booleans section to word boundary
    bools_len += 1 if (names_len + bools_len).odd?

    str_offset = HEADER_LENGTH + names_len + bools_len + (number_size * nums_len)
    table_offset = str_offset + (2 * str_count)

    {str_offset: str_offset, table_offset: table_offset}
  end

  # Reads a requested null-terminated string, bounded to the standard string
  # table. Negative offsets represent absent or cancelled capabilities.
  private def read_string_at(offset_pos : Int32, table_start : Int32, table_end : Int32) : String?
    offset = read_i16_le(offset_pos)
    return nil if offset < 0

    string_start = table_start + offset
    if string_start >= table_end
      raise ParseError.invalid_offset(string_start, table_end)
    end

    string_end = string_start
    while string_end < table_end && @data[string_end] != 0
      string_end += 1
    end

    if string_end == table_end
      raise ParseError.new(
        ParseError::Type::CorruptedString,
        "Corrupted string at offset #{string_start}: no NUL before string table end #{table_end}",
        "String crosses the declared table boundary"
      )
    end

    # String.new(Bytes) copies exactly the capability bytes, so results do not
    # retain or alias a database-sized backing buffer.
    String.new(@data[string_start, string_end - string_start])
  end

  # Reads a signed little-endian 16-bit value without pointer casts or
  # alignment assumptions. Callers establish the two-byte bound first.
  private def read_i16_le(offset : Int32) : Int16
    value = @data[offset].to_i32 | (@data[offset + 1].to_i32 << 8)
    value -= 0x10000 if value >= 0x8000
    value.to_i16
  end
end
