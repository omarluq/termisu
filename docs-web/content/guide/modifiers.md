+++
title = "Modifiers"
description = "Modifier bitflags and checks."
weight = 120
+++

# Modifiers

Compare modifiers directly with `Input::Modifier::None` to check whether none are set.
The flags-generated `none?` predicate checks inclusion of the zero-valued `None` member,
so it is not an emptiness check.

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
