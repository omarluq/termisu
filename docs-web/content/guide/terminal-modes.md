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

## Fiber Ownership

Mode scopes are reentrant in the calling fiber, so same-fiber nesting is safe.
A scope started by another fiber waits for the active scope's user block and
restoration to finish. Closing from another fiber waits for restoration and
prevents queued scopes from entering. Closing from inside the owning mode block
is rejected before teardown; close the instance after the block returns.

Do not wait inside a mode block for another fiber to enter a mode scope or close
the same `Termisu` or `Terminal`. The first fiber owns the mode until its block
returns, so those cross-fiber wait cycles cannot complete. Coordinate that work
before entering or after leaving the mode scope.
