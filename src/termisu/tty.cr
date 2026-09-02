# Low-level TTY (terminal) interface for reading from and writing to `/dev/tty`.
#
# Example:
# ```
# tty = Termisu::TTY.new
# # ... use tty ...
# tty.close
# ```
class Termisu::TTY
  private PATH = "/dev/tty"

  @out : File
  @outfd : Int32
  @infd : Int32
  @owns_input_fd : Bool
  @closed = Atomic(Bool).new(false)

  {% begin %}
    {% bsd = flag?(:openbsd) || flag?(:freebsd) %}
    private USE_RDWR  = {{ bsd }}
    private FILE_MODE = {{ bsd ? "r+" : "w" }}
  {% end %}

  getter outfd, infd

  # Opens `/dev/tty` for terminal access.
  #
  # Raises `IO::Error` if the TTY cannot be opened.
  def initialize
    @out = File.open(PATH, FILE_MODE)
    @outfd = @out.fd
    @infd = USE_RDWR ? @outfd : open_readonly_fd
    @owns_input_fd = !USE_RDWR
  end

  # Closes the TTY file descriptors.
  def close
    return unless @closed.compare_and_set(false, true)[1]

    input_fd = @owns_input_fd ? @infd : -1
    @owns_input_fd = false
    @outfd = -1
    @infd = -1

    begin
      close_output_fd
    ensure
      close_input_fd(input_fd)
    end
  end

  def write(data : String)
    @out.print(data)
  end

  def write(data : Bytes)
    @out.write(data)
  end

  def flush
    @out.flush
  end

  private def open_readonly_fd : Int32
    fd = LibC.open(PATH, LibC::O_RDONLY, 0)
    if fd == -1
      close_output_fd
      raise IO::Error.from_errno("Failed to open #{PATH}")
    end
    fd
  end

  private def close_output_fd
    @out.try(&.close)
  end

  private def close_input_fd(fd : Int32)
    LibC.close(fd) if fd >= 0
  end
end
