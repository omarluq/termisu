class Termisu::Terminfo::Parser
  MAGIC          = 0o432_i16 # 282 in decimal (standard 16-bit format)
  EXTENDED_MAGIC =   542_i16 # 542 in decimal (extended 32-bit format)
  HEADER_LENGTH  =        12

  # Parse terminfo data and return a hash of capability names to values
  def self.parse(data : Bytes, cap_names : Array(String)) : Hash(String, String)
    new(data).parse(cap_names)
  end

  def initialize(@data : Bytes)
  end

  # Parse terminfo data and return a hash mapping capability names to values
  def parse(required_caps : Array(String)) : Hash(String, String)
    io = IO::Memory.new(@data)

    header = read_header(io)
    offsets = calculate_offsets(header)
    str_count = header[4]

    # Build hash of all capabilities (index => value)
    all_caps = {} of Int32 => String

    str_count.times do |idx|
      value = read_string(io, offsets[:str_offset] + (2_i16 * idx), offsets[:table_offset])
      all_caps[idx] = value unless value.empty?
    end

    # Map required capability names to their values
    result = {} of String => String

    required_caps.each do |cap_name|
      # Find index of this capability in standard order
      if idx = Capabilities::STRING_CAPS.index(cap_name)
        if value = all_caps[idx]?
          result[cap_name] = value
        end
      end
    end

    result
  rescue
    {} of String => String
  end

  private def read_header(io : IO::Memory)
    header = StaticArray(Int16, 6).new(0)
    6.times { |idx| header[idx] = io.read_bytes(Int16, IO::ByteFormat::LittleEndian) }
    header
  end

  private def calculate_offsets(header)
    magic = header[0]
    names_len = header[1]
    bools_len = header[2]
    nums_len = header[3]
    str_count = header[4]

    number_sec_len = (magic == EXTENDED_MAGIC) ? 4_i16 : 2_i16

    # Align to word boundary
    bools_len += 1_i16 if (names_len + bools_len) % 2 != 0

    str_offset = HEADER_LENGTH.to_i16 + names_len + bools_len + (number_sec_len * nums_len)
    table_offset = str_offset + (2_i16 * str_count)

    {str_offset: str_offset, table_offset: table_offset}
  end

  private def read_string(io : IO::Memory, str_off : Int16, table : Int16) : String
    io.pos = str_off.to_i
    offset = io.read_bytes(Int16, IO::ByteFormat::LittleEndian)

    return "" if offset < 0

    io.pos = (table + offset).to_i

    bytes = [] of UInt8
    loop do
      byte = io.read_byte
      break if byte.nil? || byte == 0_u8
      bytes << byte
    end

    String.new(Slice.new(bytes.to_unsafe, bytes.size))
  rescue
    ""
  end
end
