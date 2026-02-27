+++
title = "Quick Start"
description = "First interactive TUI loop with Termisu."
weight = 20
+++

# Quick Start

This example renders text, enables mouse, and exits on `Esc` or `q`.

```crystal
require "termisu"

termisu = Termisu.new
begin
  termisu.enable_mouse
  termisu.set_cell(0, 0, 'T', fg: Termisu::Color.bright_green, attr: Termisu::Attribute::Bold)
  termisu.set_cell(1, 0, 'U', fg: Termisu::Color.bright_cyan)
  termisu.set_cell(2, 0, 'I', fg: Termisu::Color.bright_blue)
  termisu.set_cursor(3, 0)
  termisu.render

  loop do
    event = termisu.poll_event(100)
    case event
    when Termisu::Event::Key
      break if event.key.escape? || event.key.lower_q?
    when Termisu::Event::Mouse
      termisu.set_cell(event.x, event.y, '*', fg: Termisu::Color.yellow)
      termisu.render
    end
  end
ensure
  termisu.close
end
```

## Try Next

- [Runtime Config](/getting-started/configuration/)
- [Input & Events](/guide/events/)
