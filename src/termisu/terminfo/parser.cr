class Termisu::Terminfo::Parser
  MAGIC          = 0o432_i16
  EXTENDED_MAGIC = 0o542_i16
  HEADER_LENGTH  =        12

  def self.parse(data : Bytes, indices : Array(Int16)) : Array(String)
    new(data).parse(indices)
  end

  def initialize(@data : Bytes)
  end

  def parse(indices : Array(Int16)) : Array(String)
    io = IO::Memory.new(@data)

    header = read_header(io)
    offsets = calculate_offsets(header)

    indices.map do |idx|
      if idx < 0
        ""
      else
        read_string(io, offsets[:str_offset] + (2_i16 * idx), offsets[:table_offset])
      end
    end
  rescue
    Array.new(indices.size, "")
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
