+++
title = "Event Types"
description = "Key, mouse, resize, tick, and mode change payloads."
weight = 50
+++

# Event Types

`Event::Any` is:

`Event::Key | Event::Mouse | Event::Resize | Event::Tick | Event::ModeChange`

## Key Event

```crystal
event.key
event.char
event.modifiers
event.ctrl? || event.alt? || event.shift? || event.meta?
```

## Mouse Event

```crystal
event.x, event.y
event.button
event.motion?
event.press?
event.wheel?
```

## Resize Event

```crystal
event.width, event.height
event.old_width, event.old_height
event.changed?
```

## Tick Event

```crystal
event.frame
event.elapsed
event.delta
event.missed_ticks
```

## ModeChange Event

```crystal
event.mode
event.previous_mode
event.changed?
event.to_raw?
event.from_raw?
```
