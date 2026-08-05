# Project Index: Termisu

**Generated:** 2026-04-22
**Version:** 0.4.5
**Language:** Crystal (>= 1.17.0)

## Overview

Termisu is a terminal UI library providing cell-based rendering with double buffering and zero runtime dependencies. Inspired by termbox, it offers a minimal API for writing TUI applications in pure Crystal, plus a C ABI layer for embedding Termisu in non-Crystal hosts.

## Project Structure

```
src/                              # Core library (71 Crystal files)
├── termisu.cr                    # Top-level require graph
└── termisu/
    ├── termisu.cr                # Main facade & public API
    ├── version.cr                # VERSION parsed from shard.yml at compile time
    ├── terminal.cr               # High-level terminal interface
    ├── buffer.cr                 # Double-buffered cell grid
    ├── cell.cr                   # Cell (char + fg + bg + attr)
    ├── color.cr                  # Color types and modes
    ├── color/
    │   ├── conversions.cr        # Color space conversion (RGB/HSL/ANSI)
    │   ├── palette.cr            # ANSI palette definitions
    │   ├── validator.cr          # Color value validation
    │   └── formatters.cr         # Color-to-string formatting
    ├── attribute.cr              # Text attributes (bold, underline, etc.)
    ├── render_state.cr           # Batched rendering optimization
    ├── renderer.cr               # Abstract renderer interface
    ├── reader.cr                 # Buffered non-blocking input
    ├── unicode_width.cr          # East Asian wide / grapheme width
    ├── time_compat.cr            # Time API compat shim
    ├── error.cr                  # Error types
    ├── log.cr                    # Structured logging
    ├── event.cr                  # Event module & Event::Any union
    ├── event/
    │   ├── loop.cr               # Event multiplexer
    │   ├── key.cr                # Keyboard events
    │   ├── mouse.cr              # Mouse events
    │   ├── resize.cr             # Terminal resize events
    │   ├── tick.cr               # Timer tick events
    │   ├── mode_change.cr        # Mode change events
    │   ├── source.cr             # Abstract event source
    │   ├── source/
    │   │   ├── input.cr          # Keyboard/mouse source
    │   │   ├── resize.cr         # SIGWINCH source
    │   │   ├── timer.cr          # Sleep-based timer
    │   │   └── system_timer.cr   # Kernel timerfd/kqueue timer
    │   ├── poller.cr             # Poller interface
    │   └── poller/
    │       ├── linux.cr          # epoll
    │       ├── kqueue.cr         # kqueue (macOS/BSD)
    │       └── poll.cr           # poll(2) fallback
    ├── input.cr                  # Input module entry
    ├── input/
    │   ├── key.cr                # Key enum (170+ keys)
    │   ├── modifier.cr           # Ctrl/Alt/Shift/Meta flags
    │   └── parser.cr             # Escape sequence parser
    ├── terminal/
    │   ├── backend.cr            # Low-level I/O (TTY + Termios)
    │   ├── cursor.cr             # Cursor state management
    │   └── mode.cr               # Terminal mode flags
    ├── terminfo.cr               # Terminfo module entry
    ├── terminfo/
    │   ├── database.cr           # Terminfo file locator
    │   ├── parser.cr             # Binary format parser (16/32-bit magic)
    │   ├── capabilities.cr       # Capability name mappings (414 caps)
    │   ├── builtin.cr            # Fallback sequences (xterm/linux)
    │   ├── tparm.cr              # Tparm entry
    │   └── tparm/                # Parametrized string processor
    ├── tty.cr                    # /dev/tty file descriptor management
    ├── termios.cr                # Raw mode terminal configuration
    ├── system/
    │   └── poll.cr               # poll(2) syscall wrapper
    ├── lib_c/
    │   └── kqueue.cr             # kqueue LibC bindings
    ├── ffi.cr                    # C ABI module entry
    └── ffi/                      # Embeddable C FFI layer
        ├── abi.cr                # ABI version & type aliases
        ├── core.cr               # Core FFI surface
        ├── runtime.cr            # Runtime lifecycle
        ├── context.cr            # Opaque context handles
        ├── registry.cr           # Handle registry
        ├── exports.cr            # @[Extern] function exports
        ├── layout.cr             # Layout/geometry types
        ├── event_type.cr         # Event type codes
        ├── color_mode.cr         # Color mode codes
        ├── conversions.cr        # Crystal <-> C conversions
        ├── error_state.cr        # Thread-local error state
        ├── guards.cr             # Safety guards
        ├── status.cr             # Status/result codes
        └── version.cr            # FFI ABI version

spec/termisu/                     # Test suite (54 Crystal spec files)
├── input/ event/ terminal/ terminfo/ ffi/  # Mirrors src/ structure
spec/support/                     # Mock renderers, pipe helpers, mock sources
spec/shared/                      # Shared spec examples

examples/                         # Demo programs
├── demo.cr                       # Main demo
├── showcase.cr                   # Feature showcase
├── animation.cr                  # Timer-driven animation
├── colors.cr                     # Color palette
├── keyboard_and_mouse.cr         # Input demo
├── simple.cr                     # Minimal example
└── c/basic.c                     # C FFI consumer example

bench/                            # Performance benchmarks
├── bench_runner.cr
├── run.cr
└── suites/                       # buffer / parser / color suites

docs/                             # Architecture & API docs
docs-web/                         # Web documentation site
e2e/                              # End-to-end tests (TypeScript)
javascript/                       # JS bindings / platform glue
```

## Entry Points

| Entry Point | Path | Purpose |
|-------------|------|---------|
| Crystal API | `src/termisu.cr` | Public `Termisu` class facade |
| C ABI | `src/termisu/ffi/exports.cr` | Embeddable C function exports |
| CLI | `bin/hace` | Development task runner |
| Specs | `spec/spec_helper.cr` | Test configuration |
| Examples | `examples/*.cr`, `examples/c/basic.c` | Demo programs |

## Core Modules

### Termisu (Facade)
- **Path:** `src/termisu/termisu.cr`
- **Exports:** `Termisu` class
- **Purpose:** Main public API coordinating all components

### Terminal
- **Path:** `src/termisu/terminal.cr`
- **Exports:** `Terminal` class
- **Purpose:** High-level terminal interface with I/O, rendering, and mode management

### Buffer
- **Path:** `src/termisu/buffer.cr`
- **Exports:** `Buffer` class
- **Purpose:** Double-buffered cell grid with diff-based rendering

### Event Loop
- **Path:** `src/termisu/event/loop.cr`
- **Exports:** `Event::Loop` class
- **Purpose:** Async multiplexer for input/resize/timer events. Pollers under `event/poller/` select `epoll`, `kqueue`, or `poll(2)` per platform.

### Terminfo
- **Path:** `src/termisu/terminfo/`
- **Exports:** `Terminfo` module, `Database`, `Parser`, `Tparm`
- **Purpose:** Terminal capability database (414 capabilities) with full parametrized string processor

### FFI / C ABI
- **Path:** `src/termisu/ffi/`
- **Exports:** C-callable functions via `exports.cr`
- **Purpose:** Embed Termisu in C/other languages with opaque context handles, versioned ABI, and thread-local error state

### Unicode Width
- **Path:** `src/termisu/unicode_width.cr`
- **Purpose:** East Asian Wide, ambiguous, and zero-width character handling for correct grid layout

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
when Termisu::Event::Key        # Keyboard
when Termisu::Event::Mouse      # Mouse click/move/wheel
when Termisu::Event::Resize     # Terminal resize (SIGWINCH)
when Termisu::Event::Tick       # Timer tick
when Termisu::Event::ModeChange # Terminal mode switched
end
```

### Timer
```crystal
termisu.enable_timer(16.milliseconds)        # Sleep-based (portable)
termisu.enable_system_timer(16.milliseconds) # Kernel timerfd / kqueue EVFILT_TIMER
```

### Terminal Modes
```crystal
termisu.suspend { system("vim file.txt") }   # Shell-out (cooked mode)
termisu.with_password_mode { gets }          # No-echo line input
termisu.with_cbreak_mode { STDIN.read_char } # Char-by-char with echo
```

### C ABI (example)
```c
// See examples/c/basic.c
termisu_context_t ctx = termisu_new();
termisu_set_cell(ctx, 0, 0, 'H', TERMISU_COLOR_GREEN, TERMISU_COLOR_DEFAULT, 0);
termisu_render(ctx);
termisu_close(ctx);
```

## Build Commands (via `bin/hace`)

| Command | Purpose |
|---------|---------|
| `bin/hace spec` | Run tests |
| `bin/hace format` | Format code |
| `bin/hace ameba` | Run linter |
| `bin/hace all` | Format + lint + test (parallel) |
| `bin/hace demo` | Run main demo |
| `bin/hace showcase` | Feature showcase |
| `bin/hace animation` | Timer/animation demo |
| `bin/hace bench` | Release-mode benchmarks |
| `bin/hace bench-quick` | Dev-mode benchmarks |
| `bin/hace perf` | CPU profiling with perf (Linux) |
| `bin/hace callgrind` | Call graph profiling |
| `bin/hace memcheck` | Memory leak detection |

## Configuration

| File | Purpose |
|------|---------|
| `shard.yml` | Crystal dependencies and version |
| `Hacefile.yml` | Development task definitions |
| `.ameba.yml` | Linting rules |
| `lefthook.yml` | Git hooks (format, lint, test) |
| `mise.toml` | Toolchain pins |
| `biome.json`, `package.json` | JS / e2e tooling |

## Key Dependencies

- **Crystal:** >= 1.17.0 (language)
- **ameba:** Development linter (dev-only)
- **hace:** Task runner (dev-only)
- Runtime: **none** (zero runtime dependencies)

## Development Status

| Component | Status |
|-----------|--------|
| Terminal I/O | Complete |
| Terminfo | Complete |
| Double Buffering | Complete |
| Colors (16 / 256 / truecolor) | Complete |
| Attributes | Complete |
| Keyboard Input | Complete |
| Mouse Input | Complete |
| Event System | Complete |
| Async Event Loop | Complete |
| Platform Pollers (epoll/kqueue/poll) | Complete |
| Resize Events | Complete |
| Timer / System Timer | Complete |
| Terminal Modes | Complete |
| Synchronized Updates | Complete |
| Unicode / Wide Chars | In progress (see `WIDECHAR_PLAN.md`) |
| C FFI / ABI | In progress |

## Documentation

- **API Reference:** `docs/API.md`
- **Architecture:** `docs/ARCHITECTURE.md`
- **Development:** `docs/DEVELOPMENT.md`
- **E2E Testing:** `docs/E2E_TESTING_PLAN.md`
- **Wide-char plan:** `WIDECHAR_PLAN.md`
- **LLM context:** `llms.txt`
- **Meta-framework:** `.claude/INDEX.md`

## Quick Start

```bash
# Setup
shards install
shards build ameba
shards build hace

# Run tests
bin/hace spec

# Run demo
bin/hace demo
```
