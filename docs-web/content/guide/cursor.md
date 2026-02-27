+++
title = "Cursor"
description = "Cursor position and visibility controls."
weight = 30
+++

# Cursor

Cursor state is independent from text content.

```crystal
termisu.set_cursor(x, y)
termisu.hide_cursor
termisu.show_cursor
```

Set cursor after drawing if you want it to appear next to live text updates.
