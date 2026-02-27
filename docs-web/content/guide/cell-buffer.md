+++
title = "Cell Buffer"
description = "Back/front buffer behavior and rendering calls."
weight = 20
+++

# Cell Buffer

Termisu renders through a double-buffered grid:

- Back buffer receives writes via `set_cell`.
- Front buffer stores the last rendered frame.
- `render` emits only diffs.

## Core Calls

```crystal
termisu.set_cell(x, y, 'A', fg: Color.red, bg: Color.black, attr: Termisu::Attribute::Bold)
termisu.clear
termisu.render
termisu.sync
```

Use `sync` for full redraws (for example after large external changes), and `render` for normal frame updates.
