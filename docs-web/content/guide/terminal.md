+++
title = "Terminal"
description = "Terminal-level state and runtime checks."
weight = 10
+++

# Terminal

Use terminal APIs to inspect runtime state and dimensions.

```crystal
termisu.size
termisu.alternate_screen?
termisu.raw_mode?
termisu.current_mode
```

## Initialization Reminder

```crystal
termisu = Termisu.new
begin
  # app loop
ensure
  termisu.close
end
```

Always close in `ensure` so raw mode and screen state are restored.
