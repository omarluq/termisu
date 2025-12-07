module Termisu::Terminfo::Builtin
  private XTERM_FUNCS = [
    "\e[?1049h",         # smcup - enter alternate screen
    "\e[?1049l",         # rmcup - exit alternate screen
    "\e[?12l\e[?25h",    # cnorm - show cursor
    "\e[?25l",           # civis - hide cursor
    "\e[H\e[2J",         # clear - clear screen
    "\e[m\e(B",          # sgr0 - reset attributes
    "\e[4m",             # smul - underline
    "\e[1m",             # bold
    "\e[5m",             # blink
    "\e[7m",             # rev - reverse
    "\e[?1h\e=",         # smkx - enter keypad
    "\e[?1l\e>",         # rmkx - exit keypad
    "\e[38;5;%p1%dm",    # setaf - foreground color
    "\e[48;5;%p1%dm",    # setab - background color
    "\e[%i%p1%d;%p2%dH", # cup - cursor position (row, col)
    "\e[%p1%dC",         # cuf - cursor forward N
    "\e[%p1%dD",         # cub - cursor backward N
    "\e[%p1%dA",         # cuu - cursor up N
    "\e[%p1%dB",         # cud - cursor down N
    "\e[%i%p1%dG",       # hpa - horizontal position (column)
    "\e[%i%p1%dd",       # vpa - vertical position (row)
    "\e[%p1%dX",         # ech - erase N characters
    "\e[%p1%dL",         # il - insert N lines
    "\e[%p1%dM",         # dl - delete N lines
    "\e[2m",             # dim - faint/dim mode (SGR 2)
    "\e[3m",             # sitm - italic mode (SGR 3)
    "\e[8m",             # invis - hidden/invisible mode (SGR 8)
  ]

  private LINUX_FUNCS = [
    "",                  # smcup - enter alternate screen (not supported)
    "",                  # rmcup - exit alternate screen (not supported)
    "\e[?25h\e[?0c",     # cnorm - show cursor
    "\e[?25l\e[?1c",     # civis - hide cursor
    "\e[H\e[J",          # clear - clear screen
    "\e[m",              # sgr0 - reset attributes
    "\e[4m",             # smul - underline
    "\e[1m",             # bold
    "\e[5m",             # blink
    "\e[7m",             # rev - reverse
    "",                  # smkx - enter keypad (not supported)
    "",                  # rmkx - exit keypad (not supported)
    "\e[38;5;%p1%dm",    # setaf - foreground color
    "\e[48;5;%p1%dm",    # setab - background color
    "\e[%i%p1%d;%p2%dH", # cup - cursor position (row, col)
    "\e[%p1%dC",         # cuf - cursor forward N
    "\e[%p1%dD",         # cub - cursor backward N
    "\e[%p1%dA",         # cuu - cursor up N
    "\e[%p1%dB",         # cud - cursor down N
    "\e[%i%p1%dG",       # hpa - horizontal position (column)
    "\e[%i%p1%dd",       # vpa - vertical position (row)
    "\e[%p1%dX",         # ech - erase N characters
    "\e[%p1%dL",         # il - insert N lines
    "\e[%p1%dM",         # dl - delete N lines
    "\e[2m",             # dim - faint/dim mode (SGR 2)
    "\e[3m",             # sitm - italic mode (SGR 3)
    "\e[8m",             # invis - hidden/invisible mode (SGR 8)
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
