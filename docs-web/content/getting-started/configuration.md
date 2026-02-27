+++
title = "Runtime Configuration"
description = "Common Termisu runtime toggles and setup options."
weight = 30
+++

# Runtime Configuration

## Terminal Constructor

```crystal
terminal = Termisu::Terminal.new(sync_updates: true)
```

- `sync_updates: true` enables DEC synchronized updates (mode 2026) to reduce tearing.

## Input Modes

```crystal
termisu.enable_enhanced_keyboard
termisu.disable_enhanced_keyboard

termisu.enable_mouse
termisu.disable_mouse
```

## Timer Modes

```crystal
termisu.enable_timer(16.milliseconds)
termisu.enable_system_timer(16.milliseconds)
termisu.timer_interval = 8.milliseconds
termisu.disable_timer
```

Use `enable_system_timer` when you need tighter frame pacing and missed-tick tracking.

## Mode Transitions

```crystal
termisu.with_cooked_mode(preserve_screen: false) do
  system("vim README.md")
end
```

That pattern safely exits TUI mode and restores screen state afterward.
