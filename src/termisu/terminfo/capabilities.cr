module Termisu::Terminfo::Capabilities
  # Terminfo function capability indices (from ncurses term.h).
  #
  # These indices map to string capabilities in the terminfo database:
  # - Index 0-11 correspond to the 12 terminal control functions
  # - Indices are based on the standard ncurses terminfo structure
  # - Each index points to a capability string in the terminfo file
  FUNCS_INDICES = [
    28_i16, # enter_ca (smcup) - Enter alternate screen mode
    40_i16, # exit_ca (rmcup) - Exit alternate screen mode
    16_i16, # show_cursor (cnorm) - Make cursor visible
    13_i16, # hide_cursor (civis) - Make cursor invisible
    5_i16,  # clear_screen (clear) - Clear screen and home cursor
    39_i16, # sgr0 (sgr0) - Reset all attributes
    36_i16, # underline (smul) - Start underline mode
    27_i16, # bold (bold) - Start bold mode
    26_i16, # blink (blink) - Start blink mode
    30_i16, # reverse (rev) - Start reverse video mode
    89_i16, # enter_keypad (smkx) - Enable keypad transmit mode
    88_i16, # exit_keypad (rmkx) - Disable keypad transmit mode
  ]

  # Special key capability indices for terminal key sequences.
  #
  # These indices map to the key capabilities in terminfo:
  # - Indices 0-11: Function keys F1-F12
  # - Indices 12-13: Insert, Delete
  # - Indices 14-15: Home, End
  # - Indices 16-17: Page Up, Page Down
  # - Indices 18-21: Arrow keys (Up, Down, Left, Right)
  KEYS_INDICES = [
    66_i16, 68_i16, 69_i16, 70_i16, 71_i16, 72_i16,   # F1-F6
    73_i16, 74_i16, 75_i16, 67_i16, 216_i16, 217_i16, # F7-F12
    77_i16, 59_i16,                                   # Insert, Delete
    76_i16, 164_i16,                                  # Home, End
    82_i16, 81_i16,                                   # Page Up, Page Down
    87_i16, 61_i16, 79_i16, 83_i16,                   # Up, Down, Left, Right
  ]
end
