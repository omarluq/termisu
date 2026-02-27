+++
title = "API Cheatsheet"
description = "High-signal Termisu API snippets for daily use."
weight = 20
aliases = ["/reference/config/"]
+++

# API Cheatsheet

## Lifecycle

```crystal
termisu = Termisu.new
begin
  # app loop
ensure
  termisu.close
end
```

## Render + Cursor

```crystal
termisu.set_cell(x, y, 'X', fg: Termisu::Color.cyan)
termisu.set_cursor(x + 1, y)
termisu.render
termisu.sync
```

## Input

```crystal
event = termisu.poll_event(100)
if event.is_a?(Termisu::Event::Key)
  exit if event.key.escape?
end
```

## Modes

```crystal
termisu.with_cooked_mode { system("git status") }
termisu.with_password_mode { password = gets }
```

## Timers

```crystal
termisu.enable_system_timer(16.milliseconds)
termisu.disable_timer
```

## More

- API docs: <https://crystaldoc.info/github/omarluq/termisu>
- Source examples: `examples/showcase.cr`, `examples/animation.cr`
