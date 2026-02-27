+++
title = "Modifiers"
description = "Modifier bitflags and checks."
weight = 120
+++

# Modifiers

```crystal
Input::Modifier::None
Input::Modifier::Shift
Input::Modifier::Alt
Input::Modifier::Ctrl
Input::Modifier::Meta
```

## Combine and Check

```crystal
mods = Input::Modifier::Ctrl | Input::Modifier::Shift
mods.ctrl?
mods.shift?
mods.alt?
mods.meta?
```
