# Low-level TTY (terminal) interface for reading from and writing to `/dev/tty`.
#
# This class handles platform-specific differences in TTY access:
# - On OpenBSD/FreeBSD: uses a single read/write file descriptor
# - On Linux/others: uses separate read and write file descriptors
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

  {% begin %}
    {% bsd = flag?(:openbsd) || flag?(:freebsd) %}
    private USE_RDWR  = {{ bsd }}
    private FILE_MODE = {{ bsd ? "r+" : "w" }}
  {% end %}

  # Opens `/dev/tty` for terminal access.
  #
  # Raises `IO::Error` if the TTY cannot be opened.
  def initialize
    @out = File.open(PATH, FILE_MODE)
    @in = USE_RDWR ? @out : open_readonly_fd
  end

  # Closes the TTY file descriptors.
  def close
    @out.close
    close_input_fd unless USE_RDWR
  end

  private def open_readonly_fd : Int32
    fd = LibC.open(PATH, LibC::O_RDONLY, 0)
    raise IO::Error.from_errno("Failed to open #{PATH}") if fd == -1
    fd
  end

  private def close_input_fd
    LibC.close(@in.as(Int32)) if @in.is_a?(Int32)
  end
end
