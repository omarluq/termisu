# Input reader abstraction for terminal I/O.
#
# Provides buffered, non-blocking input operations with support
# for peeking, timeouts, and availability checking.
#
# EINTR Handling:
# All system calls (select, read) are wrapped with retry logic to handle
# interrupted system calls (EINTR). This ensures reliable operation when
# signals are delivered during I/O operations.
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
  Log = Termisu::Logs::Reader
  @fd : Int32
  @buffer : Bytes
  @buffer_pos : Int32 = 0
  @buffer_len : Int32 = 0

  # Maximum retry attempts for EINTR before giving up.
  # This prevents infinite loops in pathological signal storms.
  MAX_EINTR_RETRIES = 100

  # Creates a new reader for the given file descriptor.
  #
  # - `fd` - File descriptor to read from
  # - `buffer_size` - Internal buffer size (default: 128 bytes)
  def initialize(@fd : Int32, buffer_size : Int32 = 128)
    @buffer = Bytes.new(buffer_size)
    Log.debug { "Reader initialized: fd=#{@fd}, buffer_size=#{buffer_size}" }
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

  # Checks if file descriptor is readable using select(2).
  #
  # Handles EINTR by retrying the select() call automatically.
  # Other errors raise Termisu::IOError.
  private def check_fd_readable(timeout_sec : Int32 = 0, timeout_usec : Int32 = 0) : Bool
    retries = 0

    loop do
      timeval = uninitialized LibC::Timeval
      timeval.tv_sec = timeout_sec.to_i64
      timeval.tv_usec = timeout_usec.to_i64

      # Initialize fd_set - must be reset on each retry
      fd_set = uninitialized LibC::FdSet
      fd_set.fds_bits.fill(0_i64)
      word_index = @fd // 64
      bit_index = @fd % 64
      fd_set.fds_bits[word_index] = 1_i64 << bit_index

      result = LibC.select(@fd + 1, pointerof(fd_set), nil, nil, pointerof(timeval))

      if result >= 0
        return result > 0
      end

      # Handle error cases
      errno = Errno.value

      if errno.eintr?
        # Interrupted by signal - retry
        retries += 1
        if retries >= MAX_EINTR_RETRIES
          raise Termisu::IOError.select_failed(errno)
        end
        next
      end

      # EBADF: Bad file descriptor - fd was closed or invalid
      # EINVAL: Invalid timeout or nfds
      # ENOMEM: Unable to allocate memory
      raise Termisu::IOError.select_failed(errno)
    end
  end

  # Clears any buffered data.
  def clear_buffer
    @buffer_pos = 0
    @buffer_len = 0
  end

  # Closes the reader (does not close the file descriptor).
  def close
    Log.debug { "Closing reader" }
    clear_buffer
  end

  # Fills the internal buffer from the file descriptor.
  #
  # Handles EINTR by retrying the read() call automatically.
  # Returns true if data was read, false on EOF or no data available.
  # Raises Termisu::IOError on unrecoverable errors.
  private def fill_buffer : Bool
    retries = 0

    loop do
      bytes_read = LibC.read(@fd, @buffer, @buffer.size)

      if bytes_read > 0
        @buffer_pos = 0
        @buffer_len = bytes_read.to_i32
        Termisu::Logs::Reader.trace { "fill_buffer: read #{bytes_read} bytes" }
        return true
      elsif bytes_read == 0
        # EOF
        @buffer_pos = 0
        @buffer_len = 0
        Termisu::Logs::Reader.debug { "fill_buffer: EOF" }
        return false
      end

      # bytes_read < 0: error occurred
      errno = Errno.value

      if errno.eintr?
        # Interrupted by signal - retry
        retries += 1
        Termisu::Logs::Reader.trace { "fill_buffer: EINTR, retry #{retries}" }
        if retries >= MAX_EINTR_RETRIES
          Termisu::Logs::Reader.error { "fill_buffer: max EINTR retries exceeded" }
          raise Termisu::IOError.read_failed(errno)
        end
        next
      end

      if errno.eagain?
        # Non-blocking I/O would block - no data available
        @buffer_pos = 0
        @buffer_len = 0
        return false
      end

      # EBADF: Bad file descriptor
      # EIO: I/O error
      # EISDIR: fd refers to a directory
      # Other errors are unrecoverable
      Termisu::Logs::Reader.error { "fill_buffer: read error #{errno}" }
      raise Termisu::IOError.read_failed(errno)
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
