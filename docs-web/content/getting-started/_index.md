+++
title = "Getting Started"
sort_by = "weight"
reverse = false
paginate = 20
pagination_enabled = false
render = false
+++

# Getting Started

Use this section when you want a working TUI fast.

## What You Will Do

1. Install Termisu in your Crystal project.
2. Render your first frame with `set_cell` + `render`.
3. Add an event loop and clean shutdown.
4. Enable runtime features (mouse, timers, enhanced keyboard).

## Fast Path

- [Installation](/getting-started/installation/) for shard setup.
- [Quick Start](/getting-started/quick-start/) for first interactive loop.
- [Runtime Configuration](/getting-started/configuration/) for toggles and defaults.

## Exit Criteria

You are done with this section when you can run a loop that:

- draws to the screen,
- reacts to key input,
- exits cleanly with `ensure`.
