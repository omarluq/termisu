+++
title = "Timer"
description = "Sleep-based and system timers for animation/event cadence."
weight = 70
+++

# Timer

## Timer APIs

```crystal
termisu.enable_timer(16.milliseconds)
termisu.enable_system_timer(16.milliseconds)
termisu.disable_timer
termisu.timer_enabled?
termisu.timer_interval = 8.milliseconds
```

## Which Timer To Use

- `enable_timer`: portable, simple workflows.
- `enable_system_timer`: tighter cadence and `missed_ticks` tracking.

For high frame rates, prefer `enable_system_timer`.
