# Contributing to Termisu

Thank you for your interest in contributing to Termisu! This document provides guidelines and information to help you get started.

## Table of Contents

- [Development Setup](#development-setup)
- [Project Architecture](#project-architecture)
- [Debugging with Logs](#debugging-with-logs)
- [Running Tests](#running-tests)
- [Code Style](#code-style)
- [Submitting Changes](#submitting-changes)

## Development Setup

### Prerequisites

- [Crystal](https://crystal-lang.org/install/) >= 1.18.2
- Hace task runner (installed via shards)
- [Lefthook](https://github.com/evilmartians/lefthook#install) - Git hooks manager

### Setup

1. Clone the repository:

```bash
git clone https://github.com/omarluq/termisu.git
cd termisu
```

2. Install dependencies and build tools:

```bash
shards install
shards build hace
```

3. Install git hooks:

```bash
lefthook install
```

4. Run tests:

```bash
bin/hace spec
```

5. Run examples:

```bash
bin/hace demo
bin/hace colors
```

## Project Architecture

```
src/termisu/
├── termisu.cr              # Main entry point and public API
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
│   └── backend.cr          # Low-level I/O (TTY + Termios)
├── tty.cr                  # /dev/tty file descriptor management
├── termios.cr              # Raw mode terminal configuration
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

### Module Overview

| Module       | Responsibility                                          |
| ------------ | ------------------------------------------------------- |
| **Termisu**  | Facade class providing the public API                   |
| **Terminal** | High-level terminal operations (screen, cursor, colors) |
| **Buffer**   | Double-buffered cell grid with diff-based rendering     |
| **Reader**   | Non-blocking input with EINTR handling                  |
| **Terminfo** | Terminal capability database access                     |
| **Color**    | Multi-mode color support (ANSI-8, ANSI-256, RGB)        |
| **Logging**  | Structured logging for debugging                        |

## Debugging with Logs

Termisu uses a structured logging system for debugging. Since stdout is used for terminal rendering, logs are written to a file.

### Configuration

Set these environment variables before running your application:

```bash
# Log level: trace, debug, info, warn, error, fatal, none
export TERMISU_LOG_LEVEL=debug

# Log file path (default: /tmp/termisu.log)
export TERMISU_LOG_FILE=/tmp/termisu.log

# Dispatch mode: true=sync (real-time), false=async (better performance)
export TERMISU_LOG_SYNC=true
```

### Watching Logs

In a separate terminal, tail the log file:

```bash
tail -f /tmp/termisu.log
```

### Log Levels

| Level   | Use Case                              |
| ------- | ------------------------------------- |
| `trace` | Detailed per-byte/per-cell operations |
| `debug` | Component lifecycle, state changes    |
| `info`  | Initialization, configuration         |
| `warn`  | Recoverable issues                    |
| `error` | Unrecoverable errors                  |

### Component Logs

Each component has its own log source for filtering:

```crystal
Termisu::Log              # Main library log
Termisu::Logs::Terminal   # Terminal init, screen management
Termisu::Logs::Buffer     # Cell operations, rendering
Termisu::Logs::Reader     # Input reading
Termisu::Logs::Render     # Render state optimization
Termisu::Logs::Input      # Key/byte processing
Termisu::Logs::Color      # Color operations
Termisu::Logs::Terminfo   # Terminfo database
```

### Adding Logs to Your Code

```crystal
# In a component file
Log = Termisu::Logs::MyComponent

def my_method
  Log.debug { "Processing input: #{value}" }
  Log.trace { "Detailed step: #{detail}" }
end
```

## Running Tests

```bash
# Run all tests
bin/hace spec

# Run specific test file
crystal spec spec/termisu/buffer_spec.cr

# Run with verbose output
crystal spec --verbose
```

### Available Tasks

Run `bin/hace --list` to see all available tasks. Key tasks:

| Task                  | Description                   |
| --------------------- | ----------------------------- |
| `bin/hace spec`       | Run crystal spec              |
| `bin/hace demo`       | Run demo example              |
| `bin/hace colors`     | Run colors example            |
| `bin/hace format`     | Format code                   |
| `bin/hace ameba`      | Run Ameba linter              |
| `bin/hace all`        | Format, lint, and test        |
| `bin/hace bench`      | Run benchmarks (release mode) |
| `bin/hace bench-quick`| Run benchmarks (dev mode)     |
| `bin/hace clean`      | Clean build artifacts         |

### Pre-commit Hooks

The project uses Lefthook for pre-commit hooks. They run automatically on commit:

- `bin/hace format` - Code formatting
- `bin/hace ameba` - Static analysis
- `yamlfmt` - YAML formatting

To run hooks manually:

```bash
lefthook run pre-commit
```

## Code Style

- Follow Crystal's standard formatting (`bin/hace format`)
- Use `bin/hace ameba` for static analysis
- Keep methods focused and small
- Document public methods with Crystal doc comments
- Use meaningful variable and method names

### Example

```crystal
# Good: Clear documentation and focused method
# Sets a cell at the specified position in the buffer.
#
# Parameters:
# - x: Column position (0-based)
# - y: Row position (0-based)
# - ch: Character to display
#
# Returns false if coordinates are out of bounds.
def set_cell(x : Int32, y : Int32, ch : Char) : Bool
  return false if out_of_bounds?(x, y)
  @buffer[y * @width + x] = ch
  true
end
```

## Submitting Changes

1. **Fork** the repository
2. **Create a branch** for your feature or fix
3. **Write tests** for new functionality
4. **Run `bin/hace all`** to format, lint, and test
5. **Commit** with a clear message
6. **Push** and create a Pull Request

### Commit Message Format

```
Add feature description

- Bullet points for specific changes
- Keep it concise but informative
```

### Pull Request Guidelines

- Reference any related issues
- Describe what changed and why
- Include test coverage for new features
- Update documentation if needed

## Questions?

Open an issue if you have questions or need guidance on a contribution.
