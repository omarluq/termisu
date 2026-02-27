+++
title = "Keys"
description = "Key event helpers and key-matching predicates."
weight = 110
+++

# Keys

## Key Event Fields

```crystal
event.key
event.char
event.modifiers
```

## Modifier Checks

```crystal
event.ctrl?
event.alt?
event.shift?
event.meta?
```

## Common Helpers

```crystal
event.ctrl_c?
event.ctrl_d?
event.ctrl_q?
event.ctrl_z?
```

## Key Matching

```crystal
event.key.escape?
event.key.enter?
event.key.tab?
event.key.back_tab?
event.key.up?
event.key.down?
event.key.left?
event.key.right?
event.key.home?
event.key.end?
event.key.page_up?
event.key.page_down?
event.key.f1?
event.key.f12?
event.key.q?
event.key.lower_q?
event.key.upper_q?
```
