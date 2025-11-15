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
  @in : File | Int32
  @outfd : Int32
  @infd : Int32

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
    @in = USE_RDWR ? @out : open_readonly_fd
    @outfd = @out.fd
    @infd = USE_RDWR ? @outfd : @in.as(Int32)
  end

  # Closes the TTY file descriptors.
  def close
    close_output_fd
    close_input_fd unless USE_RDWR
  end

  def write(data : String)
    @out.print(data)
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

  private def close_input_fd
    LibC.close(@in.as(Int32)) if @in.is_a?(Int32)
  end
end
