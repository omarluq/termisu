+++
title = "Events"
description = "Event polling and event-loop patterns."
weight = 40
+++

# Events

All runtime input flows through `Event::Any`.

## Polling APIs

```crystal
# Blocking
event = termisu.poll_event
event = termisu.wait_event

# Timeout
event = termisu.poll_event(100)
event = termisu.poll_event(100.milliseconds)

# Non-blocking
event = termisu.try_poll_event
```

## Iterator Pattern

```crystal
termisu.each_event do |event|
  case event
  when Termisu::Event::Key
  when Termisu::Event::Mouse
  when Termisu::Event::Resize
  when Termisu::Event::Tick
  when Termisu::Event::ModeChange
  end
end
```
