+++
title = "Installation"
description = "Install Termisu in a Crystal project."
weight = 10
+++

# Installation

## Requirements

- Crystal `>= 1.18.2`
- POSIX terminal environment (`/dev/tty` access)

## Add Dependency

Update your `shard.yml`:

```yaml
dependencies:
  termisu:
    github: omarluq/termisu
```

Install:

```bash
shards install
```

## Verify In A File

Create `src/main.cr`:

```crystal
require "termisu"
puts Termisu::VERSION
```

Run:

```bash
crystal run src/main.cr
```

If it prints a version string, wiring is done.
