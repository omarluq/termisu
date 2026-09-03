# Mock helpers for testing terminal components without real TTY access.
module MockHelpers
  # Creates a mock terminfo database with valid structure.
  #
  # Supports both standard (0o432) and extended (0o542) magic numbers.
  def create_mock_terminfo_data(magic = 0o432_i16) : Bytes
    io = IO::Memory.new

    # Write header (6 Int16 values)
    io.write_bytes(magic, IO::ByteFormat::LittleEndian)  # magic
    io.write_bytes(10_i16, IO::ByteFormat::LittleEndian) # names section length
    io.write_bytes(0_i16, IO::ByteFormat::LittleEndian)  # boolean section length
    io.write_bytes(5_i16, IO::ByteFormat::LittleEndian)  # numbers section length
    io.write_bytes(10_i16, IO::ByteFormat::LittleEndian) # string count
    io.write_bytes(50_i16, IO::ByteFormat::LittleEndian) # string table size (10 strings * 5 bytes)

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

    # Write string table (10 strings of "test\0" = 50 bytes total)
    10.times do
      io.write("test\0".to_slice)
    end

    io.to_slice
  end

  # Creates a sparse terminfo database containing named string capabilities.
  # Entries in *malformed_caps* receive an out-of-range string offset while the
  # rest of the file remains structurally valid.
  def create_sparse_terminfo_data(
    capabilities : Hash(String, String),
    malformed_caps : Array(String) = [] of String,
  ) : Bytes
    names = capabilities.keys + malformed_caps
    highest_index = names.reduce(0) do |highest, name|
      index = mock_string_cap_index(name)
      index > highest ? index : highest
    end
    string_count = highest_index + 1
    offsets = Array(Int16).new(string_count, -1_i16)
    table = IO::Memory.new

    capabilities.each do |name, value|
      offsets[mock_string_cap_index(name)] = table.pos.to_i16
      table.write(value.to_slice)
      table.write_byte(0_u8)
    end

    malformed_caps.each do |name|
      offsets[mock_string_cap_index(name)] = Int16::MAX
    end

    io = IO::Memory.new
    io.write_bytes(0o432_i16, IO::ByteFormat::LittleEndian)
    io.write_bytes(6_i16, IO::ByteFormat::LittleEndian) # names section length
    io.write_bytes(0_i16, IO::ByteFormat::LittleEndian)
    io.write_bytes(0_i16, IO::ByteFormat::LittleEndian)
    io.write_bytes(string_count.to_i16, IO::ByteFormat::LittleEndian)
    io.write_bytes(table.size.to_i16, IO::ByteFormat::LittleEndian)
    io.write("test\0\0".to_slice)
    offsets.each { |offset| io.write_bytes(offset, IO::ByteFormat::LittleEndian) }
    io.write(table.to_slice)
    io.to_slice
  end

  # Exposes *data* as the database for *term_name* for the duration of the block.
  def with_mock_terminfo_database(term_name : String, data : Bytes, &)
    temp = File.tempfile("termisu-terminfo")
    root = temp.path
    temp.close
    File.delete(root)

    entry_dir = File.join(root, term_name[0].to_s)
    entry_path = File.join(entry_dir, term_name)
    Dir.mkdir_p(entry_dir)
    File.write(entry_path, data)

    original_term = ENV["TERM"]?
    original_terminfo = ENV["TERMINFO"]?
    ENV["TERM"] = term_name
    ENV["TERMINFO"] = root
    Termisu::Terminfo.clear_caps_cache

    yield
  ensure
    Termisu::Terminfo.clear_caps_cache
    if original_term
      ENV["TERM"] = original_term
    else
      ENV.delete("TERM")
    end
    if original_terminfo
      ENV["TERMINFO"] = original_terminfo
    else
      ENV.delete("TERMINFO")
    end

    File.delete(entry_path) if entry_path && File.exists?(entry_path)
    Dir.delete(entry_dir) if entry_dir && Dir.exists?(entry_dir)
    Dir.delete(root) if root && Dir.exists?(root)
  end

  private def mock_string_cap_index(name : String) : Int32
    Termisu::Terminfo::Capabilities.string_cap_index(name) ||
      raise ArgumentError.new("Unknown terminfo capability: #{name}")
  end
end
