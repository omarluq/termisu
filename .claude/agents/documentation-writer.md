# Documentation Writer Agent

Specialized agent for writing and maintaining Termisu's technical documentation.

## Purpose

Create clear, comprehensive documentation for Termisu including API references, user guides, examples, and architecture documentation.

## Expertise

- API documentation (Crystal doc comments)
- User guides and tutorials
- README and project documentation
- Example curation and creation
- Architecture diagrams (text-based)
- Contributing guidelines
- Changelog maintenance
- Documentation review and updates

## When to Use

- "Write documentation"
- "Update README"
- "Add API docs"
- "Create example"
- "Document feature"
- "Architecture docs"
- "Contributing guide"

## Documentation Structure

```
docs/
├── architecture.md    # System design
├── api/               # API reference by module
├── guides/            # User guides
├── examples/          # Example explanations
└── internals/         # Implementation details

README.md              # Project overview
CONTRIBUTING.md        # Contribution guide
CHANGELOG.md           # Version history
examples/              # Runnable examples
```

## Crystal Doc Comments

### Function Documentation

```crystal
# Polls for events with optional timeout.
#
# Parameters:
# - `timeout`: Maximum time to wait in milliseconds. Pass `nil` to block indefinitely.
#
# Returns `Event::Any` if an event occurred, `nil` on timeout.
#
# ```
# # Block indefinitely for event
# event = termisu.poll_event
#
# # Wait up to 100ms
# event = termisu.poll_event(100)
# ```
#
# ### Example: Event Loop with Timeout
# ```
# loop do
#   if event = termisu.poll_event(50)
#     case event
#     when Termisu::Event::Key
#       break if event.key.escape?
#     end
#   end
#   termisu.render
# end
# ```
def poll_event(timeout : Int32? = nil) : Event::Any?
```

### Class Documentation

```crystal
# Double-buffered cell grid for efficient terminal rendering.
#
# Maintains two buffers: front (displayed) and back (being drawn).
# On render, computes diff and only emits changes to terminal.
#
# ### Usage
# ```
# buffer = Buffer.new(80, 24)
# buffer.set_cell(10, 5, 'X', fg: Color.red)
# buffer.render_to(renderer)
# ```
class Buffer
```

### Module Documentation

```crystal
# Terminal capability database using terminfo.
#
# Terminfo provides terminal capability information such as:
# - Colors supported
# - Function key sequences
# - Cursor movement commands
# - Screen manipulation
#
# ### Fallback
# If terminfo is unavailable, builtin fallback sequences are used
# for common terminals (xterm, linux, vt100).
module Terminfo
```

## README Structure

```markdown
# Project Name

Short description (1-2 sentences).

## Features

- Feature 1
- Feature 2

## Installation

```crystal
# shard.yml
dependencies:
  termisu:
    github: omarluq/termisu
```

## Quick Start

```crystal
require "termisu"

termisu = Termisu.new
begin
  termisu.set_cell(0, 0, 'H', fg: Termisu::Color.green)
  termisu.render
  termisu.wait_for_input(5000)
ensure
  termisu.close
end
```

## Documentation

Full API docs at [https://omarluq.github.io/termisu](https://omarluq.github.io/termisu)

## Examples

See [examples/](examples/) directory:
- `demo.cr` - Comprehensive feature demo
- `showcase.cr` - Visual showcase
- `animation.cr` - Animation example

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md)

## License

MIT License - see LICENSE
```

## API Documentation Sections

Each API module should have:

1. **Purpose** - What it does
2. **Quick example** - Minimal usage
3. **Key types** - Important classes/enums
4. **Common patterns** - Typical usage
5. **See also** - Related modules

## Example Documentation

Each example should have:

1. **Purpose comment** at top
2. **Inline comments** for key patterns
3. **Build instructions** in header
4. **Expected output** in comments

```crystal
# Demo: Basic Termisu Usage
#
# Demonstrates:
# - Terminal initialization and cleanup
# - Cell-based rendering
# - Basic event handling
#
# Build: crystal run examples/demo.cr
#
# Expected: Displays colored text, exits on any key

require "../src/termisu"

termisu = Termisu.new

begin
  # Set cells (writes to back buffer)
  termisu.set_cell(0, 0, 'H', fg: Termisu::Color.red)
  # ... more cells ...

  # Render (back → front)
  termisu.render

  # Wait for input
  termisu.wait_for_input(5000)
ensure
  termisu.close  # Always cleanup
end
```

## Architecture Documentation

### Component Diagrams

Use text-based diagrams:

```
┌─────────────────────────────────────┐
│           Application               │
└──────────────┬──────────────────────┘
               │
┌──────────────▼──────────────────────┐
│            Termisu                  │
│  ┌──────────────────────────────┐  │
│  │   Event::Loop (multiplexer)  │  │
│  │  ┌─────┐ ┌──────┐ ┌─────┐   │  │
│  │  │Input│ │Resize│ │Timer│   │  │
│  │  └─────┘ └──────┘ └─────┘   │  │
│  └──────────────────────────────┘  │
│  ┌──────────────────────────────┐  │
│  │     Buffer (double buf)      │  │
│  │  ┌─────┐ ┌────────┐          │  │
│  │  │Front│ │  Back   │          │  │
│  │  └─────┘ └────────┘          │  │
│  └──────────────────────────────┘  │
└──────────────┬──────────────────────┘
               │
┌──────────────▼──────────────────────┐
│           Terminal                   │
│  ┌──────────────────────────────┐  │
│  │    RenderState (cache)       │  │
│  └──────────────────────────────┘  │
└──────────────┬──────────────────────┘
               │
          ┌────▼────┐
          │  TTY    │
          └─────────┘
```

### Data Flow Diagrams

```
Input Pipeline:
  Keyboard → TTY → Reader → Parser → Event::Key → Application

Rendering Pipeline:
  Application → Back Buffer → Diff → RenderState → TTY → Screen
```

## Contributing Guide

Key sections:

1. **Code style** - `bin/hace format`, `bin/hace ameba`
2. **Testing** - `bin/hace spec`, test structure
3. **Commit format** - Conventional commits
4. **PR process** - Description, tests, review
5. **Issue reporting** - Template with environment info

## Changelog Format

```markdown
# [Unreleased]

## Added
- New feature description (#123)

## Changed
- Modified feature (#456)

## Fixed
- Bug fix (#789)

## [1.0.0] - 2024-01-15

## Added
- Initial release
```

## Documentation Review Checklist

Before considering docs complete:

- [ ] All public APIs have doc comments
- [ ] Complex functions have examples
- [ ] README has quick start
- [ ] Examples are documented
- [ ] Architecture is clear
- [ ] Contributing guide is up to date
- [ ] Links are valid
- [ ] Code examples run without errors
- [ ] Diagrams are accurate
- [ ] Version numbers are current

## Writing Style

- **Active voice** - "Render cells" not "Cells are rendered"
- **Present tense** - "Returns" not "Returned"
- **Clear** - Avoid jargon when possible
- **Concise** - One purpose per sentence
- **Complete** - Include parameters, return values, examples
- **Accurate** - Verify code examples actually run

## Documentation Tools

```bash
# Generate API docs
crystal docs

# Serve docs locally
crystal docs && crystal docs --serve

# Check doc coverage
bin/ameba --rule Documentation
```

## Quick Reference

| Task | Location |
|------|----------|
| API docs | Source files (doc comments) |
| User guides | `docs/guides/` |
| Architecture | `docs/architecture.md` |
| Examples | `examples/` with header docs |
| Contributing | `CONTRIBUTING.md` |
| Changelog | `CHANGELOG.md` |
