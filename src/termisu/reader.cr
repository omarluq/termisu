# Input reader abstraction for terminal I/O.
#
# Provides buffered, non-blocking input operations with support
# for peeking, timeouts, and availability checking.
#
# Example:
# ```
# terminal = Termisu::Terminal.new
# reader = Termisu::Reader.new(terminal.infd)
#
# if byte = reader.read_byte
#   puts "Read: #{byte.chr}"
# end
#
# reader.close
# ```
class Termisu::Reader
  @fd : Int32
  @buffer : Bytes
  @buffer_pos : Int32 = 0
  @buffer_len : Int32 = 0

  # Creates a new reader for the given file descriptor.
  #
  # - `fd` - File descriptor to read from
  # - `buffer_size` - Internal buffer size (default: 128 bytes)
  def initialize(@fd : Int32, buffer_size : Int32 = 128)
    @buffer = Bytes.new(buffer_size)
  end

  # Reads a single byte from the input.
  #
  # Returns `nil` if no data is available or on EOF.
  # This is a non-blocking operation when the terminal is in raw mode.
  def read_byte : UInt8?
    fill_buffer if @buffer_pos >= @buffer_len
    return nil if @buffer_pos >= @buffer_len

    byte = @buffer[@buffer_pos]
    @buffer_pos += 1
    byte
  end

  # Reads exactly `count` bytes from the input.
  #
  # Returns `nil` if fewer than `count` bytes are available.
  # Blocks until all bytes are read or timeout occurs.
  def read_bytes(count : Int32) : Bytes?
    result = Bytes.new(count)
    bytes_read = 0

    while bytes_read < count
      byte = read_byte
      return nil unless byte
      result[bytes_read] = byte
      bytes_read += 1
    end

    result
  end

  # Peeks at the next byte without consuming it.
  #
  # Returns `nil` if no data is available.
  def peek_byte : UInt8?
    fill_buffer if @buffer_pos >= @buffer_len
    return nil if @buffer_pos >= @buffer_len

    @buffer[@buffer_pos]
  end

  # Checks if data is available for reading.
  #
  # Uses select(2) with zero timeout for non-blocking check.
  def available? : Bool
    return true if @buffer_pos < @buffer_len

    check_fd_readable(0)
  end

  # Waits for data with a timeout.
  #
  # - `timeout_ms` - Timeout in milliseconds
  #
  # Returns `true` if data becomes available, `false` on timeout.
  def wait_for_data(timeout_ms : Int32) : Bool
    return true if @buffer_pos < @buffer_len

    # Convert milliseconds to seconds and microseconds
    timeout_sec = timeout_ms // 1000
    timeout_usec = (timeout_ms % 1000) * 1000

    check_fd_readable(timeout_sec, timeout_usec)
  end

  # Checks if file descriptor is readable using select(2)
  private def check_fd_readable(timeout_sec : Int32 = 0, timeout_usec : Int32 = 0) : Bool
    timeval = uninitialized LibC::Timeval
    timeval.tv_sec = timeout_sec.to_i64
    timeval.tv_usec = timeout_usec.to_i64

    # Initialize fd_set
    fd_set = uninitialized LibC::FdSet
    # Zero out the set
    fd_set.fds_bits.fill(0_i64)
    # Set the bit for our file descriptor
    word_index = @fd // 64
    bit_index = @fd % 64
    fd_set.fds_bits[word_index] = 1_i64 << bit_index

    # Call select with proper error handling
    result = LibC.select(@fd + 1, pointerof(fd_set), nil, nil, pointerof(timeval))

    # Check for errors
    if result < 0
      raise IO::Error.from_errno("select failed")
    end

    result > 0
  end

  # Clears any buffered data.
  def clear_buffer
    @buffer_pos = 0
    @buffer_len = 0
  end

  # Closes the reader (does not close the file descriptor).
  def close
    clear_buffer
  end

  private def fill_buffer
    bytes_read = LibC.read(@fd, @buffer, @buffer.size)
    if bytes_read > 0
      @buffer_pos = 0
      @buffer_len = bytes_read.to_i32
    else
      @buffer_pos = 0
      @buffer_len = 0
    end
  end
end

# Add FdSet and related types to LibC if not already defined
lib LibC
  {% unless LibC.has_constant?(:FdSet) %}
    struct FdSet
      fds_bits : StaticArray(Int64, 16)
    end
  {% end %}

  {% unless LibC.has_constant?(:Timeval) %}
    struct Timeval
      tv_sec : Int64
      tv_usec : Int64
    end
  {% end %}

  fun select(nfds : Int32, readfds : FdSet*, writefds : FdSet*, errorfds : FdSet*, timeout : Timeval*) : Int32
end
