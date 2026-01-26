# Termisu Development Workflow

Development commands and patterns for Termisu TUI library.

## When to Use

- "Build the project"
- "Run tests"
- "Format code"
- "Setup dependencies"
- "Run benchmarks"

## Quick Commands

```bash
# Setup (after cloning)
shards install
shards build ameba
shards build hace

# Common tasks
bin/hace spec           # Run all tests
bin/hace format         # Format code
bin/hace ameba          # Run linter
bin/hace all            # Format, lint, and test (parallel)
```

## Task Reference (Hacefile.yml)

### Core Development

| Command | Purpose |
|---------|---------|
| `bin/hace spec` | Run tests (with unbuffer for TTY) |
| `bin/hace format` | Format code with crystal tool format |
| `bin/hace format:check` | Check formatting without modifying |
| `bin/hace ameba` | Run Ameba linter |
| `bin/hace ameba:fix` | Run linter with auto-fix |
| `bin/hace clean` | Clean build artifacts |
| `bin/hace all` | Format + lint + test (parallel) |

### Examples

| Command | Purpose |
|---------|---------|
| `bin/hace demo` | Run demo.cr |
| `bin/hace showcase` | Run showcase.cr |
| `bin/hace animation` | Run animation.cr |
| `bin/hace kmd` | Run keyboard_and_mouse.cr |
| `bin/hace colors` | Run colors.cr |
| `bin/hace modes` | Run modes.cr |

### Benchmarks

| Command | Purpose |
|---------|---------|
| `bin/hace bench` | Release mode benchmarks |
| `bin/hace bench-quick` | Dev mode (faster compile) |

### Profiling (Linux)

| Command | Purpose |
|---------|---------|
| `bin/hace perf` | CPU profiling with perf |
| `bin/hace callgrind` | Call graph profiling |
| `bin/hace memcheck` | Memory leak detection |

### E2E Testing

| Command | Purpose |
|---------|---------|
| `bin/hace e2e:install` | Install E2E dependencies |
| `bin/hace e2e:build` | Build Crystal binaries for E2E |
| `bin/hace e2e:test` | Run E2E tests |
| `bin/hace e2e:all` | Build + test |

## Direct Crystal Commands

```bash
# Run all tests
crystal spec

# Run specific test file
crystal spec spec/termisu/buffer_spec.cr

# Run with verbose output
crystal spec --verbose

# Run with error trace
crystal spec --error-trace

# Format code
crystal tool format

# Check formatting
crystal tool format --check

# Build example (dev mode)
crystal run examples/demo.cr

# Build example (release mode)
crystal build examples/demo.cr -o bin/demo --release
```

## Development Workflow

### 1. Watch Mode

```bash
# Watch for changes and run tests
watch -n 1 crystal spec
```

### 2. Linting

```bash
# Run linter
bin/ameba

# Auto-fix issues
bin/ameba --fix
```

### 3. Type Checking

```bash
# Check type hierarchy
crystal tool hierarchy src/termisu.cr
```

## Configuration Files

| File | Purpose |
|------|---------|
| `shard.yml` | Crystal dependencies and version |
| `Hacefile.yml` | Development task definitions |
| `.ameba.yml` | Linting rules |
| `lefthook.yml` | Git hooks |

## Dependencies

### Runtime

Zero runtime dependencies - pure Crystal.

### Development

| Dependency | Purpose |
|------------|---------|
| `ameba` | Linting |
| `hace` | Task runner |

## CI/CD

### Test Workflow (.github/workflows/test.yml)

- Multi-OS testing (Linux, macOS)
- Unbuffer for TTY emulation
- Verbose test output

### E2E Workflow (.github/workflows/e2e.yml)

- Builds binaries per OS
- Tests multiple shells (bash, zsh, fish)
- Uses tui-test framework

## Code Quality

```bash
# Full check (format + lint + test)
bin/hace all

# Format check (without modifying)
bin/hace format:check

# Check before committing
git diff --name-only | xargs crystal tool format --check
```

## Troubleshooting

### Logging

```bash
# Enable debug logging
TERMISU_LOG_LEVEL=debug TERMISU_LOG_FILE=/tmp/termisu.log crystal run examples/demo.cr

# View logs
tail -f /tmp/termisu.log
```

### Performance

```bash
# Profile with perf
bin/hace perf

# Check memory leaks
bin/hace memcheck
```
