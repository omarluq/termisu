# Termisu Meta-Framework Index

Guide to using Claude Code with the Termisu TUI library.

## Quick Start

New to Termisu? Start here:

1. **Learn the basics**: Read [PROJECT_INDEX.md](../PROJECT_INDEX.md)
2. **Try examples**: Run `bin/hace demo` or `bin/hace showcase`
3. **Build TUI apps**: Use [termisu-tui.md](skills/termisu-tui.md) skill
4. **Run tests**: Use [crystal-testing.md](skills/crystal-testing.md) skill

## Meta-Framework Structure

```
.claude/
├── INDEX.md                  # This file - framework overview
├── AGENTS.md                 # Agent directory
├── skills/                   # Reusable workflows
│   ├── crystal-testing.md    # Crystal spec testing
│   ├── termisu-tui.md        # TUI patterns and idioms
│   └── termisu-workflow.md   # Development commands
├── rules/                    # Code conventions
│   ├── crystal-conventions.md    # Naming and formatting
│   ├── terminal-patterns.md      # Mode switching patterns
│   ├── event-loop-patterns.md    # Async event handling
│   ├── rendering-patterns.md     # Drawing and optimization
│   └── commit-workflow.md        # Git standards and quality
└── agents/                   # Specialist agents
    ├── tui-developer.md          # TUI application builder
    ├── termisu-core-dev.md       # Termisu library developer
    ├── event-system-agent.md     # Event loop expert
    ├── terminologist.md          # Terminfo specialist
    ├── colorist.md               # Color system expert
    ├── input-parser-dev.md       # Input parsing expert
    └── crystal-tester.md         # Testing expert
```

## Skills

Skills provide reusable workflows and patterns.

| Skill | Purpose | When to Use |
|-------|---------|-------------|
| [crystal-testing.md](skills/crystal-testing.md) | Crystal spec testing | "Write a test", "How do I test?" |
| [termisu-tui.md](skills/termisu-tui.md) | TUI development patterns | "Create TUI app", "Handle input" |
| [termisu-workflow.md](skills/termisu-workflow.md) | Development commands | "Run tests", "Format code" |

## Rules

Rules define code conventions and standards.

| Rule | Purpose |
|------|---------|
| [crystal-conventions.md](rules/crystal-conventions.md) | Naming, formatting, code structure |
| [terminal-patterns.md](rules/terminal-patterns.md) | Terminal mode handling |
| [event-loop-patterns.md](rules/event-loop-patterns.md) | Async event patterns |
| [rendering-patterns.md](rules/rendering-patterns.md) | Drawing and optimization |
| [commit-workflow.md](rules/commit-workflow.md) | Git, linting, formatting |

## Agents

Agents are specialists for specific domains.

**For TUI Apps:**
- [tui-developer.md](agents/tui-developer.md)

**For Termisu Core:**
- [termisu-core-dev.md](agents/termisu-core-dev.md)
- [event-system-agent.md](agents/event-system-agent.md)
- [terminologist.md](agents/terminologist.md)
- [colorist.md](agents/colorist.md)
- [input-parser-dev.md](agents/input-parser-dev.md)

**For Testing:**
- [crystal-tester.md](agents/crystal-tester.md)

## Common Workflows

### Create a TUI Application

1. Read [termisu-tui.md](skills/termisu-tui.md) for patterns
2. Use [tui-developer](agents/tui-developer.md) agent for implementation
3. Follow [crystal-conventions.md](rules/crystal-conventions.md) for code style
4. Run `bin/hace demo` for reference

### Add Feature to Termisu

1. Read [PROJECT_INDEX.md](../PROJECT_INDEX.md) for architecture
2. Use appropriate specialist agent (e.g., [terminologist.md](agents/terminologist.md))
3. Follow [crystal-conventions.md](rules/crystal-conventions.md)
4. Add tests using [crystal-testing.md](skills/crystal-testing.md)
5. Run `bin/hace all` before committing

### Fix Bug in Termisu

1. Identify affected component (event, color, terminfo, etc.)
2. Use appropriate domain agent
3. Write test first (TDD pattern)
4. Verify fix with `bin/hace spec`
5. Check [commit-workflow.md](rules/commit-workflow.md) before committing

## Development Commands

```bash
# Setup
shards install
shards build ameba
shards build hace

# Development
bin/hace spec           # Run tests
bin/hace format         # Format code
bin/hace ameba          # Run linter
bin/hace all            # All checks (parallel)

# Examples
bin/hace demo           # Main demo
bin/hace showcase       # Feature showcase
bin/hace animation      # Animation example
bin/hace colors         # Color palette

# Benchmarks
bin/hace bench          # Release mode
bin/hace bench-quick    # Dev mode
```

## Quality Checklist

Before committing or submitting PR:

- [ ] `bin/hace format` - Code formatted
- [ ] `bin/hace ameba` - No lint issues
- [ ] `bin/hace spec` - All tests pass
- [ ] Commit message follows format (see [commit-workflow.md](rules/commit-workflow.md))
- [ ] Documentation updated
- [ ] Examples still work

## Learning Resources

- **Project docs**: [docs/](../docs/) directory
- **Examples**: [examples/](../examples/) directory
- **Specs**: [spec/](../spec/) for usage examples
- **Source**: [src/termisu/](../src/termisu/) for implementation

## Getting Help

1. Check [PROJECT_INDEX.md](../PROJECT_INDEX.md) for overview
2. Check relevant skill or rule file
3. Run examples: `bin/hace demo`
4. Check test files for usage patterns

## Contributing

1. Follow [crystal-conventions.md](rules/crystal-conventions.md)
2. Add tests for new features
3. Update documentation
4. Run `bin/hace all` before committing
5. Follow [commit-workflow.md](rules/commit-workflow.md)

## Roadmap

- **v0.3.0** ✅ - Current: Full color support, complete event system
- **v0.5.0** - Widget system (layout, reusable components)
- **v0.6.0** - Advanced rendering (scrollable regions, viewports)
- **v1.0.0** - Production ready (stable API, complete docs)

## Version

Termisu v0.3.0
Crystal >= 1.18.2
