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
# ## Usage
#
# ```
# data = File.read("/usr/share/terminfo/x/xterm-256color")
# caps = Parser.parse(data, ["clear", "bold", "smcup"])
# ```
class Termisu::Terminfo::Parser
  # Magic number for standard 16-bit terminfo format.
  MAGIC = 0o432_i16

  # Magic number for extended 32-bit terminfo format.
  EXTENDED_MAGIC = 542_i16

  # Size of terminfo binary header in bytes.
  HEADER_LENGTH = 12

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
  # Returns empty hash on parse errors.
  def self.parse(data : Bytes, cap_names : Array(String)) : Hash(String, String)
    new(data).parse(cap_names)
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
  def parse(required_caps : Array(String)) : Hash(String, String)
    io = IO::Memory.new(@data)

    header = read_header(io)
    offsets = calculate_offsets(header)
    string_count = header[4]

    # Parse all string capabilities from binary format
    all_capabilities = parse_all_strings(io, string_count, offsets)

    # Filter to only requested capabilities
    extract_requested_capabilities(all_capabilities, required_caps)
  rescue
    {} of String => String
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
    StaticArray(Int16, 6).new do |i|
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
  # The null-terminated string, or empty string if offset is -1 or on error.
  private def read_string_at(io : IO::Memory, offset_pos : Int16, table_start : Int16) : String
    io.pos = offset_pos.to_i
    offset = io.read_bytes(Int16, IO::ByteFormat::LittleEndian)

    return "" if offset < 0

    io.pos = (table_start + offset).to_i
    read_null_terminated_string(io)
  rescue
    ""
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
