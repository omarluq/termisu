# Project Index: Termisu

**Generated:** 2025-01-25
**Version:** 0.3.0
**Language:** Crystal (>= 1.18.2)

## Overview

Termisu is a terminal UI library providing cell-based rendering with double buffering and zero runtime dependencies. Inspired by termbox, it offers a minimal API for writing TUI applications in pure Crystal.

## Project Structure

```
src/termisu/          # Core library (45 files)
├── termisu.cr        # Main facade & public API
├── buffer.cr         # Double-buffered cell grid
├── terminal.cr       # High-level terminal interface
├── cell.cr           # Cell (char + fg + bg + attr)
├── color.cr          # Color types and modes
├── attribute.cr      # Text attributes (bold, underline, etc.)
├── cursor.cr         # Cursor state management
├── render_state.cr   # Batched rendering optimization
├── reader.cr         # Buffered non-blocking input
├── event.cr          # Event::Any union type
├── event/
│   ├── loop.cr       # Event multiplexer
│   ├── key.cr        # Keyboard events
│   ├── mouse.cr      # Mouse events
│   ├── resize.cr     # Terminal resize events
│   ├── tick.cr       # Timer tick events
│   ├── mode_change.cr # Mode change events
│   ├── source.cr     # Abstract event source
│   ├── source/input.cr    # Keyboard/mouse source
│   ├── source/resize.cr   # SIGWINCH source
│   ├── source/timer.cr    # Sleep-based timer
│   ├── source/system_timer.cr # Kernel timer
│   └── poller/*.cr   # Platform-specific pollers (epoll/kqueue/poll)
├── input/
│   ├── key.cr        # Key enum (170+ keys)
│   ├── modifier.cr   # Ctrl/Alt/Shift/Meta flags
│   └── parser.cr     # Escape sequence parser
├── terminal/
│   ├── backend.cr    # Low-level I/O (TTY + Termios)
│   └── mode.cr       # Terminal mode flags
├── terminfo/
│   ├── database.cr   # Terminfo file locator
│   ├── parser.cr     # Binary format parser
│   ├── builtin.cr    # Fallback sequences
│   └── tparm/        # Parametrized string processor
├── tty.cr            # /dev/tty file descriptor
├── termios.cr        # Raw mode configuration
├── error.cr          # Error types
└── log.cr            # Structured logging

spec/termisu/         # Test suite (50+ files)
examples/             # 7 demo programs
bench/                # Performance benchmarks
docs/                 # Architecture & API docs
e2e/                  # End-to-end tests (TypeScript)
```

## Entry Points

| Entry Point | Path | Purpose |
|-------------|------|---------|
| Main API | `src/termisu.cr` | Public `Termisu` class facade |
| CLI | `bin/hace` | Development task runner |
| Specs | `spec/spec_helper.cr` | Test configuration |
| Examples | `examples/*.cr` | Demo programs |

## Core Modules

### Termisu (Facade)
- **Path:** `src/termisu.cr`
- **Exports:** `Termisu` class
- **Purpose:** Main public API coordinating all components

### Terminal
- **Path:** `src/termisu/terminal.cr`
- **Exports:** `Terminal` class
- **Purpose:** High-level terminal interface with I/O and rendering

### Buffer
- **Path:** `src/termisu/buffer.cr`
- **Exports:** `Buffer` class
- **Purpose:** Double-buffered cell grid with diff-based rendering

### Event Loop
- **Path:** `src/termisu/event/loop.cr`
- **Exports:** `Event::Loop` class
- **Purpose:** Async multiplexer for input/resize/timer events

### Terminfo
- **Path:** `src/termisu/terminfo/`
- **Exports:** `Terminfo` module, Database, Parser, Tparm
- **Purpose:** Terminal capability database (414 capabilities)

## Key APIs

### Rendering
```crystal
termisu.set_cell(x, y, 'A', fg: Color.red, bg: Color.black, attr: Attribute::Bold)
termisu.clear
termisu.render  # Diff-based
termisu.sync    # Full redraw
```

### Events
```crystal
event = termisu.poll_event(100.milliseconds)
case event
when Termisu::Event::Key    # Keyboard
when Termisu::Event::Mouse  # Mouse click/move
when Termisu::Event::Resize # Terminal resize
when Termisu::Event::Tick   # Timer tick
end
```

### Timer
```crystal
termisu.enable_timer(16.milliseconds)        # Sleep-based
termisu.enable_system_timer(16.milliseconds) # Kernel timerfd/kqueue
```

### Terminal Modes
```crystal
termisu.suspend { system("vim file.txt") }          # Shell-out
termisu.with_password_mode { gets }                  # Hidden input
termisu.with_cbreak_mode { STDIN.read_char }        # Echo input
```

## Build Commands (via `bin/hace`)

| Command | Purpose |
|---------|---------|
| `bin/hace spec` | Run tests |
| `bin/hace format` | Format code |
| `bin/hace ameba` | Run linter |
| `bin/hace all` | Format + lint + test (parallel) |
| `bin/hace demo` | Run main demo |
| `bin/hace bench` | Release mode benchmarks |
| `bin/hace perf` | CPU profiling with perf |
| `bin/hace e2e:test` | End-to-end tests |

## Configuration

| File | Purpose |
|------|---------|
| `shard.yml` | Crystal dependencies and version |
| `Hacefile.yml` | Development task definitions |
| `.ameba.yml` | Linting rules |
| `lefthook.yml` | Git hooks |

## Key Dependencies

- **Crystal:** >= 1.18.2 (language)
- **ameba:** Development linter
- **hace:** Task runner

## Development Status

| Component | Status |
|-----------|--------|
| Terminal I/O | Complete |
| Terminfo | Complete |
| Double Buffering | Complete |
| Colors | Complete |
| Attributes | Complete |
| Keyboard Input | Complete |
| Mouse Input | Complete |
| Event System | Complete |
| Async Event Loop | Complete |
| Resize Events | Complete |
| Timer/Tick Events | Complete |
| Terminal Modes | Complete |
| Synchronized Updates | Complete |
| Unicode/Wide Chars | Planned |

## Documentation

- **API Reference:** `docs/API.md`
- **Architecture:** `docs/ARCHITECTURE.md`
- **Development:** `docs/DEVELOPMENT.md`
- **E2E Testing:** `docs/E2E_TESTING_PLAN.md`

## Quick Start

```bash
# Setup
shards install
shards build ameba hace

# Run tests
bin/hace spec

# Run demo
bin/hace demo
```
