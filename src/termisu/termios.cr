# Terminal attribute manipulation - raw mode, etc.
class Termisu::Termios
  @fd : Int32
  @original : LibC::Termios?

  def initialize(@fd : Int32)
  end

  def enable_raw_mode : Nil
    @original = get_attrs

    tios = @original.not_nil!.dup

    # Input flags - turn off input processing
    tios.c_iflag &= ~(LibC::IGNBRK | LibC::BRKINT | LibC::PARMRK |
                      LibC::ISTRIP | LibC::INLCR | LibC::IGNCR |
                      LibC::ICRNL | LibC::IXON)

    # Local flags - turn off canonical mode, echo, signals
    tios.c_lflag &= ~(LibC::ECHO | LibC::ECHONL | LibC::ICANON |
                      LibC::ISIG | LibC::IEXTEN)

    # Control flags - set 8 bit chars
    tios.c_cflag &= ~(LibC::CSIZE | LibC::PARENB)
    tios.c_cflag |= LibC::CS8

    # Control chars - set raw mode read behavior
    tios.c_cc[LibC::VMIN] = 1_u8   # minimum number of characters for read
    tios.c_cc[LibC::VTIME] = 0_u8  # timeout in deciseconds for read

    set_attrs(tios)
  end

  def restore : Nil
    if original = @original
      set_attrs(original)
    end
  end

  private def get_attrs : LibC::Termios
    tios = uninitialized LibC::Termios
    if LibC.tcgetattr(@fd, pointerof(tios)) != 0
      raise IO::Error.from_errno("tcgetattr failed")
    end
    tios
  end

  private def set_attrs(tios : LibC::Termios) : Nil
    # Create a copy to pass to tcsetattr
    tios_copy = tios
    if LibC.tcsetattr(@fd, LibC::TCSAFLUSH, pointerof(tios_copy)) != 0
      raise IO::Error.from_errno("tcsetattr failed")
    end
  end
end
