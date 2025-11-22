module Termisu::Terminfo::Builtin
  private XTERM_FUNCS = [
    "\e[?1049h",      # enter_ca
    "\e[?1049l",      # exit_ca
    "\e[?12l\e[?25h", # show_cursor
    "\e[?25l",        # hide_cursor
    "\e[H\e[2J",      # clear_screen
    "\e[m\e(B",       # sgr0
    "\e[4m",          # underline
    "\e[1m",          # bold
    "\e[5m",          # blink
    "\e[7m",          # reverse
    "\e[?1h\e=",      # enter_keypad
    "\e[?1l\e>",      # exit_keypad
    "\e[38;5;%p1%dm", # setaf (256-color foreground)
    "\e[48;5;%p1%dm", # setab (256-color background)
  ]

  private LINUX_FUNCS = [
    "",               # enter_ca
    "",               # exit_ca
    "\e[?25h\e[?0c",  # show_cursor
    "\e[?25l\e[?1c",  # hide_cursor
    "\e[H\e[J",       # clear_screen
    "\e[m",           # sgr0
    "\e[4m",          # underline
    "\e[1m",          # bold
    "\e[5m",          # blink
    "\e[7m",          # reverse
    "",               # enter_keypad
    "",               # exit_keypad
    "\e[38;5;%p1%dm", # setaf (256-color foreground)
    "\e[48;5;%p1%dm", # setab (256-color background)
  ]

  private XTERM_KEYS = [
    "\eOP", "\eOQ", "\eOR", "\eOS",         # F1-F4
    "\e[15~", "\e[17~", "\e[18~", "\e[19~", # F5-F8
    "\e[20~", "\e[21~", "\e[23~", "\e[24~", # F9-F12
    "\e[2~", "\e[3~", "\e[H", "\e[F",       # Insert, Delete, Home, End
    "\e[5~", "\e[6~",                       # PgUp, PgDn
    "\e[A", "\e[B", "\e[D", "\e[C",         # Up, Down, Left, Right
  ]

  private LINUX_KEYS = [
    "\e[[A", "\e[[B", "\e[[C", "\e[[D", "\e[[E",      # F1-F5
    "\e[17~", "\e[18~", "\e[19~", "\e[20~", "\e[21~", # F6-F10
    "\e[23~", "\e[24~",                               # F11-F12
    "\e[2~", "\e[3~", "\e[1~", "\e[4~",               # Insert, Delete, Home, End
    "\e[5~", "\e[6~",                                 # PgUp, PgDn
    "\e[A", "\e[B", "\e[D", "\e[C",                   # Up, Down, Left, Right
  ]

  def self.funcs_for(name : String) : Array(String)
    linux?(name) ? LINUX_FUNCS : XTERM_FUNCS
  end

  def self.keys_for(name : String) : Array(String)
    linux?(name) ? LINUX_KEYS : XTERM_KEYS
  end

  private def self.linux?(name : String) : Bool
    name.includes?("linux")
  end
end
