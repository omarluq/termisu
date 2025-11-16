# Mock helpers for testing terminal components without real TTY access
module MockHelpers
  # Creates a mock terminfo database with valid structure
  # Supports both standard (0o432) and extended (0o542) magic numbers
  def create_mock_terminfo_data(magic = 0o432_i16) : Bytes
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

  # Helper to temporarily set TERM environment variable
  def with_term(value : String?, &)
    original = ENV["TERM"]?
    begin
      if value
        ENV["TERM"] = value
      else
        ENV.delete("TERM")
      end
      yield
    ensure
      if original
        ENV["TERM"] = original
      else
        ENV.delete("TERM")
      end
    end
  end

  # Check if we can actually use /dev/tty
  def tty_available? : Bool
    File.exists?("/dev/tty") && File.writable?("/dev/tty")
  rescue
    false
  end
end
