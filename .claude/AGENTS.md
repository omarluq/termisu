# Termisu Agent Directory

Meta-framework agents for Termisu TUI development.

## Overview

This directory contains specialized agents for Termisu development:
- **Application developers** use agents to build TUI apps with Termisu
- **Library developers** use agents to extend Termisu itself
- **Agents** provide focused expertise on specific domains

## Agent Categories

### For TUI Application Development

| Agent | Purpose | When to Use |
|-------|---------|-------------|
| [tui-developer.md](tui-developer.md) | Build TUI applications using Termisu | "Create a TUI app", "Add animation", "Handle keyboard" |

### For Library Development (Termisu Core)

| Agent | Purpose | When to Use |
|-------|---------|-------------|
| [termisu-core-dev.md](termisu-core-dev.md) | Implement Termisu core components | "Add feature to Termisu", "Fix buffer rendering" |
| [event-system-agent.md](event-system-agent.md) | Event loop and async patterns | "Custom event source", "Event loop debugging" |
| [terminologist.md](terminologist.md) | Terminfo database and capabilities | "Add terminfo capability", "Fix terminfo parsing" |
| [colorist.md](colorist.md) | Color system implementation | "Add color format", "Convert colors" |
| [input-parser-dev.md](input-parser-dev.md) | Input parsing and keyboard/mouse | "Parse escape sequence", "Add key support" |

### For Testing

| Agent | Purpose | When to Use |
|-------|---------|-------------|
| [crystal-tester.md](crystal-tester.md) | Crystal spec testing patterns | "Write a test for", "Add unit tests" |

## Agent Selection Guide

### I want to build a TUI app
→ Use **tui-developer**

### I want to fix a bug in Termisu
→ Use **termisu-core-dev** + appropriate domain agent

### I want to add a new terminfo capability
→ Use **terminologist**

### I want to add a new key sequence
→ Use **input-parser-dev**

### I want to add a new color format
→ Use **colorist**

### I want to add a custom event source
→ Use **event-system-agent**

### I want to write tests
→ Use **crystal-tester**

## Agent Content Structure

Each agent file contains:

1. **Purpose** - What the agent specializes in
2. **Expertise** - Specific capabilities
3. **When to Use** - Trigger phrases
4. **Core Patterns** - Code examples
5. **Common Tasks** - How-to guides
6. **Testing Patterns** - Test examples
7. **Troubleshooting** - Common issues

## Related Meta-Framework

- **Skills** (../skills/) - Reusable workflows and patterns
- **Rules** (../rules/) - Code conventions and guidelines
- **INDEX.md** - Project overview and quick reference
