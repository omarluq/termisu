class Termisu
  VERSION = "0.0.1.alpha"

  @tty : TTY
  @termios : Termios
  @terminfo : Terminfo

  def initialize
    @tty = TTY.new
    @termios = Termios.new(@tty.outfd)
    @terminfo = Terminfo.new

    @termios.enable_raw_mode
    enter_alternate_screen
  end

  def close
    exit_alternate_screen
    @termios.restore
    @tty.close
  end

  private def enter_alternate_screen
    @tty.write(@terminfo.enter_ca)
    @tty.write(@terminfo.enter_keypad)
    @tty.write(@terminfo.hide_cursor)
    @tty.write(@terminfo.clear_screen)
    @tty.flush
  end

  private def exit_alternate_screen
    @tty.write(@terminfo.show_cursor)
    @tty.write(@terminfo.exit_keypad)
    @tty.write(@terminfo.exit_ca)
    @tty.flush
  end

  def clear
  end

  def present
  end

  def put_cell(x : Int32, y : Int32, cell : Termisu::Cell)
  end

  def change_cell(x : Int32, y : Int32, ch : UInt32, fg : UInt16, bg : UInt16)
  end

  def blit(x : Int32, y : Int32, h : Int32, cell : Termisu::Cell)
  end

  def select_input_mode(mode : Termisu::InputMode) : Bool
  end

  def peek_event(event : Termisu::Event, timeout : Int32) : Int32
  end

  def poll_event(event : Termisu::Event) : Int32
  end
end

require "./termisu/*"
