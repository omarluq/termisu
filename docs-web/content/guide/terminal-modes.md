+++
title = "Terminal Modes"
description = "Mode switching for shell-out, password, and cbreak workflows."
weight = 80
+++

# Terminal Modes

Use mode switching for shell commands, secure input, and custom termios behavior.

## Common Mode Wrappers

```crystal
termisu.with_cooked_mode(preserve_screen: false) do
  system("vim file.txt")
end

termisu.with_password_mode do
  print "Password: "
  password = gets.try(&.chomp)
end

termisu.with_cbreak_mode do
  print "Press any key: "
  char = STDIN.read_char
end
```

## Custom Mode

```crystal
custom = Termisu::Terminal::Mode::Echo | Termisu::Terminal::Mode::Signals
termisu.with_mode(custom, preserve_screen: true) do
  # custom terminal behavior
end
```

Mode transitions emit `Event::ModeChange` events.
