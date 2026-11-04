{% if flag?(:win32) %}
  require "./system/console/output"
{% end %}

# Owns terminal I/O independently of redirected standard streams.
class Termisu::TTY
  private PATH = "/dev/tty"

  {% if flag?(:win32) %}
    @console_output : System::Console::Output?
  {% else %}
    @out : IO::FileDescriptor
  {% end %}
  @outfd : IO::FileDescriptor::Handle
  @infd : IO::FileDescriptor::Handle
  @owns_input_fd : Bool
  @closed = Atomic(Bool).new(false)

  {% begin %}
    {% bsd = flag?(:openbsd) || flag?(:freebsd) %}
    private USE_RDWR  = {{ bsd }}
    private FILE_MODE = {{ bsd ? "r+" : "w" }}
  {% end %}

  getter outfd, infd

  # Opens the controlling terminal; never allocates or attaches a console.
  {% if flag?(:win32) %}
    def initialize
      @infd = @outfd = 0_u64
      @owns_input_fd = false
      begin
        @outfd = open_console("CONOUT$").address
        @infd = open_console("CONIN$").address
        @owns_input_fd = true
        @console_output = System::Console::Output.new(@outfd)
      rescue error
        close rescue nil
        raise error
      end
    end
  {% else %}
    def initialize
      @out = File.open(PATH, FILE_MODE)
      @outfd = @out.fd
      @infd = USE_RDWR ? @outfd : open_readonly_fd
      @owns_input_fd = !USE_RDWR
    end
  {% end %}

  def close
    return unless @closed.compare_and_set(false, true)[1]

    {% if flag?(:win32) %}
      output_fd, input_fd = @outfd, @infd
      @outfd = @infd = 0_u64
      @owns_input_fd = false
      error : Exception? = nil
      begin
        @console_output.try(&.finish)
      rescue ex
        error = ex
      end
      @console_output = nil
      [output_fd, input_fd].each do |fd|
        if fd != 0 && LibC.CloseHandle(LibC::HANDLE.new(fd)) == 0
          close_error = IO::Error.from_winerror("CloseHandle(TTY)")
          error ||= close_error
        end
      end
      raise error if error
    {% else %}
      input_fd = @owns_input_fd ? @infd : -1
      @owns_input_fd = false
      @outfd = @infd = -1
      begin
        close_output_fd
      ensure
        close_input_fd(input_fd)
      end
    {% end %}
  end

  def write(data : String)
    {% if flag?(:win32) %}
      write(data.to_slice)
    {% else %}
      @out.print(data)
    {% end %}
  end

  def write(data : Bytes)
    {% if flag?(:win32) %}
      console_output.write(data)
    {% else %}
      @out.write(data)
    {% end %}
  end

  def flush
    {% if flag?(:win32) %}
      console_output.flush
    {% else %}
      @out.flush
    {% end %}
  end

  {% if flag?(:win32) %}
    private def console_output : System::Console::Output
      @console_output || raise IO::Error.new("TTY is closed")
    end

    private def open_console(name : String) : LibC::HANDLE
      path = name.to_utf16
      handle = LibC.CreateFileW(path, LibC::GENERIC_READ | LibC::GENERIC_WRITE,
        LibC::FILE_SHARE_READ | LibC::FILE_SHARE_WRITE, nil, LibC::OPEN_EXISTING, 0_u32, nil)
      if handle == LibC::INVALID_HANDLE_VALUE
        raise IO::Error.from_winerror("CreateFileW(#{name}); an attached console is required")
      end
      handle
    end
  {% else %}
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
  {% end %}
end
