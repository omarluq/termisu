# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

> **Meta-Framework Available:** See `.claude/INDEX.md` for specialized skills, rules, and agents for Termisu development. The meta-framework provides comprehensive workflows for TUI development, testing, and library contributions.

## Build and Development Commands

```bash
# Setup (after cloning)
shards install
shards build ameba
shards build hace

# Common tasks (use bin/hace)
bin/hace spec           # Run all tests
bin/hace format         # Format code
bin/hace ameba          # Run linter
bin/hace all            # Format, lint, and test (parallel)

# Run specific test file
crystal spec spec/termisu/buffer_spec.cr

# Run examples
bin/hace demo           # Main demo
bin/hace showcase       # Showcase example
bin/hace animation      # Animation with timer events
bin/hace colors         # Color palette showcase
bin/hace kmd            # Keyboard and mouse demo
bin/hace modes          # Terminal modes demo
crystal run examples/simple.cr  # Minimal example

# Benchmarks
bin/hace bench          # Release mode benchmarks
bin/hace bench-quick    # Dev mode (faster compile)

# Profiling (Linux)
bin/hace perf           # CPU profiling with perf
bin/hace callgrind      # Call graph profiling
bin/hace memcheck       # Memory leak detection
```

## Architecture Overview

Termisu is a terminal UI library providing cell-based rendering with double buffering. Zero runtime dependencies.

### Core Component Flow

```
Termisu (facade)
    |
    +-- Terminal (I/O + rendering)
    |       |-- Backend (raw TTY/Termios)
    |       |-- Terminfo (capability database)
    |       +-- Buffer (double-buffered cells)
    |               |-- Cell (char + fg + bg + attr)
    |               |-- Cursor (position + visibility)
    |               +-- RenderState (escape sequence optimization)
    |
    +-- Event::Loop (async multiplexer)
            |-- Event::Source::Input (keyboard/mouse)
            |-- Event::Source::Resize (SIGWINCH)
            +-- Event::Source::Timer (animation ticks)
```

### Key Abstractions

**Renderer Interface** (`src/termisu/renderer.cr`): Abstract interface that Buffer renders to. Terminal implements this. Enables testing with mock renderers.

**Event::Source** (`src/termisu/event/source.cr`): Abstract class for async event producers. Custom sources extend this to add events to the loop.

**Event::Any** (`src/termisu/event.cr`): Union type `Key | Mouse | Resize | Tick | ModeChange` for type-safe event handling.

### Rendering Pipeline

1. User calls `set_cell(x, y, char, fg, bg, attr)` on Termisu facade
2. Cell written to Buffer's back buffer
3. On `render()`, Buffer diffs front vs back buffers
4. RenderState tracks terminal state to minimize escape sequences
5. Only changed cells emitted; consecutive same-styled cells batched
6. Front buffer updated to match back buffer

### Input Pipeline

1. Event::Source::Input reads from TTY in dedicated fiber
2. Input::Parser decodes escape sequences (CSI, SS3, Kitty protocol)
3. Events sent to Event::Loop's output channel
4. User receives via `poll_event`, `try_poll_event`, or `each_event`

### Terminfo System

- `Database`: Locates terminfo files in standard paths
- `Parser`: Parses binary format (supports 16-bit and 32-bit magic)
- `Builtin`: Fallback sequences for xterm/linux when terminfo unavailable
- `Tparm`: Full parametrized string processor with stack, variables, conditionals

## Testing Patterns

- Specs mirror src/ structure in spec/termisu/
- Mock renderers in `spec/support/mock_renderers.cr` for Buffer tests
- Pipe helpers in `spec/support/pipe_helpers.cr` for Reader/Input tests
- Event source mocks in `spec/support/mock_sources.cr`

## Logging

Logs go to file (stdout is for rendering). Configure via environment:

```bash
TERMISU_LOG_LEVEL=debug    # trace, debug, info, warn, error, fatal, none
TERMISU_LOG_FILE=/tmp/termisu.log
TERMISU_LOG_SYNC=true      # sync for real-time, async for performance
```

Watch logs: `tail -f /tmp/termisu.log`

## Code Conventions

- All public classes under `Termisu::` namespace
- Value types (struct) for Cell, Color, RenderState
- `Atomic(Bool)` for thread-safe state in async components
- State caching pattern in Terminal to avoid redundant escape sequences
- EINTR retry loops in Reader for robust I/O

## Project Structure

```
src/termisu/
├── termisu.cr              # Main facade (public API)
├── terminal.cr             # High-level terminal interface
├── buffer.cr               # Double-buffered cell grid
├── cell.cr                 # Individual cell (char + style)
├── color.cr                # Color types and modes
├── color/
│   ├── conversions.cr      # Color space conversion algorithms
│   ├── validator.cr        # Color value validation
│   ├── palette.cr          # ANSI color palette definitions
│   └── formatters.cr       # Color string formatting
├── attribute.cr            # Text attributes (bold, underline, etc.)
├── cursor.cr               # Cursor state management
├── renderer.cr             # Abstract renderer interface
├── render_state.cr         # Batched rendering optimization
├── reader.cr               # Buffered non-blocking input
├── error.cr                # Error types
├── log.cr                  # Structured logging system
├── terminal/
│   ├── backend.cr          # Low-level I/O (TTY + Termios)
│   └── mode.cr             # Terminal mode flags (raw, cooked, etc.)
├── tty.cr                  # /dev/tty file descriptor management
├── termios.cr              # Raw mode terminal configuration
├── event.cr                # Event module and Event::Any union type
├── event/
│   ├── key.cr              # Keyboard events
│   ├── mouse.cr            # Mouse events
│   ├── resize.cr           # Terminal resize events
│   ├── tick.cr             # Timer tick events
│   ├── mode_change.cr      # Mode change events
│   ├── source.cr           # Abstract event source class
│   ├── loop.cr             # Event multiplexer
│   └── source/
│       ├── input.cr        # Keyboard/mouse event source
│       ├── resize.cr       # SIGWINCH event source
│       └── timer.cr        # Timer tick source
├── input.cr                # Input module entry
├── input/
│   ├── key.cr              # Key enum and definitions
│   ├── modifier.cr         # Modifier flags (Ctrl, Alt, Shift)
│   └── parser.cr           # Escape sequence parser
└── terminfo/
    ├── terminfo.cr         # Capability access interface
    ├── database.cr         # Terminfo file locator
    ├── parser.cr           # Binary format parser
    ├── capabilities.cr     # Capability name mappings
    ├── builtin.cr          # Fallback sequences
    └── tparm/
        ├── tparm.cr        # Parametrized string processor
        ├── processor.cr    # Stack-based interpreter
        ├── operations.cr   # O(1) operation dispatch
        ├── conditional.cr  # If-then-else handling
        ├── variables.cr    # Variable storage
        └── output.cr       # Output formatting
```

## Key Patterns

### Event Loop Pattern

```crystal
termisu = Termisu.new
termisu.enable_timer(16.milliseconds)  # Optional: for animation

loop do
  case event = termisu.poll_event
  when Termisu::Event::Key
    break if event.key.escape?
  when Termisu::Event::Resize
    termisu.sync
  when Termisu::Event::Tick
    # Animation frame
  end
  termisu.render
end

termisu.close
```

### Custom Event Source

```crystal
class MySource < Termisu::Event::Source
  def start(output : Channel(Event::Any)) : Nil
    # Spawn fiber to produce events
  end
  def stop : Nil
  def running? : Bool
  def name : String
end

termisu.add_event_source(MySource.new)
```

### Terminal Modes

Termisu supports switching between terminal modes for shell-out operations,
password input, and other scenarios requiring different terminal behavior.

**Available Modes:**

| Mode        | Behavior                                 | Use Case                     |
| ----------- | ---------------------------------------- | ---------------------------- |
| raw         | No processing, char-by-char              | Full TUI control (default)   |
| cooked      | Line buffering, echo, signals            | Shell-out, external programs |
| cbreak      | Char-by-char with echo and signals       | Interactive prompts          |
| password    | Line buffering, no echo                  | Secure password entry        |
| semi_raw    | Char-by-char with signals (Ctrl+C works) | TUI with graceful exit       |
| full_cooked | Full terminal driver processing          | Complete shell emulation     |

**Shell-out Pattern (recommended):**

```crystal
termisu.suspend do
  # Exits alternate screen, enables cooked mode
  system("vim file.txt")
end
# TUI fully restored
```

**Password Input:**

```crystal
password = termisu.with_password_mode do
  print "Password: "
  gets.try(&.chomp)
end
```

**Custom Mode Combinations:**

```crystal
# Char-by-char with echo but no signals
custom = Termisu::Terminal::Mode::Echo
termisu.with_mode(custom) do
  # Custom input handling
end
```

**Mode Change Events:**

```crystal
termisu.each_event do |event|
  case event
  when Termisu::Event::ModeChange
    puts "Mode: #{event.previous_mode} -> #{event.mode}"
  end
end
```

## Claude Code Meta-Framework

The `.claude/` directory contains specialized resources for AI-assisted development:

### Skills (8 total)

**TUI Development:**

- `termisu-tui.md` - TUI patterns and idioms
- `termisu-input.md` - Keyboard, mouse, and input mode patterns
- `termisu-async.md` - Fiber-based async patterns

**Development Workflow:**

- `crystal-testing.md` - Crystal spec testing patterns
- `termisu-workflow.md` - Development commands and build system
- `termisu-performance.md` - Profiling, benchmarking, optimization
- `termisu-debugging.md` - Debugging techniques and troubleshooting

### Rules (8 total)

**Crystal Conventions:**

- `crystal-conventions.md` - Naming, formatting, code structure
- `crystal-patterns.md` - Advanced idioms (struct vs class, generics, macros)
- `crystal-ffi.md` - LibC bindings and platform-specific code
- `crystal-concurrency.md` - Fiber coordination and thread safety

**TUI Patterns:**

- `terminal-patterns.md` - Mode switching and cleanup
- `event-loop-patterns.md` - Async event handling
- `rendering-patterns.md` - Double-buffering and optimization

**Quality:**

- `commit-workflow.md` - Git standards, linting, formatting

### Agents (10 total)

**For TUI Application Development:**

- `tui-developer.md` - Build TUI applications using Termisu

**For Library Development (Termisu Core):**

- `termisu-core-dev.md` - Implement Termisu core components
- `event-system-agent.md` - Event loop and custom event sources
- `terminologist.md` - Terminfo database and capabilities
- `colorist.md` - Color system implementation
- `input-parser-dev.md` - Input parsing and keyboard/mouse handling
- `rendering-optimization-agent.md` - Performance optimization specialist
- `async-io-agent.md` - Async I/O and systems programming
- `documentation-writer.md` - Technical documentation specialist

**For Testing:**

- `crystal-tester.md` - Crystal spec testing patterns

### Quick Reference by Task

| Task                  | Use                                                         |
| --------------------- | ----------------------------------------------------------- |
| **Build TUI app**     | `termisu-tui.md`, `tui-developer.md`                        |
| **Handle input**      | `termisu-input.md`                                          |
| **Async patterns**    | `termisu-async.md`, `crystal-concurrency.md`                |
| **Write tests**       | `crystal-testing.md`, `crystal-tester.md`                   |
| **Profile/optimize**  | `termisu-performance.md`, `rendering-optimization-agent.md` |
| **Debug issues**      | `termisu-debugging.md`                                      |
| **Add feature**       | `termisu-core-dev.md` + domain agent                        |
| **Platform code**     | `crystal-ffi.md`, `crystal-patterns.md`                     |
| **Before committing** | `commit-workflow.md`                                        |
| **Write docs**        | `documentation-writer.md`                                   |

## File Index

| Path                  | Purpose                          |
| --------------------- | -------------------------------- |
| `.claude/INDEX.md`    | Meta-framework overview          |
| `.claude/AGENTS.md`   | Agent directory                  |
| `.claude/skills/*.md` | Reusable workflows               |
| `.claude/rules/*.md`  | Code conventions                 |
| `.claude/agents/*.md` | Specialist agents                |
| `PROJECT_INDEX.md`    | Project overview (LLM-optimized) |
| `README.md`           | User-facing documentation        |
| `CONTRIBUTING.md`     | Contribution guidelines          |
