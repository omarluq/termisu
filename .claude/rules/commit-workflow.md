# Commit & Quality Workflow

Commit standards, linting, and formatting rules for Termisu development.

## When to Use

- "Create a commit"
- "Format code"
- "Run linter"
- "Pre-commit checks"
- "Quality checks"

## Pre-Commit Checklist

**Before committing, ALWAYS run:**

```bash
# Format code
bin/hace format

# Run linter
bin/hace ameba

# Run tests
bin/hace spec

# Or all at once (parallel)
bin/hace all
```

## Commit Standards

### Commit Message Format

```
<type>(<scope>): <subject>

<body>

<footer>
```

### Types

| Type | Purpose | Example |
|------|---------|---------|
| `feat` | New feature | `feat(buffer): add clear_region method` |
| `fix` | Bug fix | `fix(event): prevent duplicate timer events` |
| `refactor` | Code change without functional change | `refactor(parser): simplify escape sequence parsing` |
| `perf` | Performance improvement | `perf(render): batch consecutive cells with same style` |
| `test` | Adding or updating tests | `test(buffer): add coverage for edge cases` |
| `docs` | Documentation only | `docs(readme): update installation instructions` |
| `chore` | Maintenance tasks | `chore(deps): update ameba to version` |
| `style` | Code style changes (formatting) | `style(format): run crystal tool format` |

### Subject Line

- Imperative mood ("add" not "added" or "adds")
- Lower case after type/scope
- No period at end
- Max 50 characters

```
Good: feat(event): add keyboard repeat support
Bad: Added keyboard repeat support.
Bad: feat(Event): Add Keyboard Repeat Support.
```

### Body

- What was changed and why
- Reference issues if applicable
- Wrap at 72 characters

```
feat(buffer): add clear_region method

Previously, clearing required full buffer clear. This adds
region-based clearing for better performance when updating
small areas.

Fixes #42
```

### Examples

```
feat(input): add enhanced keyboard support

Implements Kitty keyboard protocol and modifyOtherKeys to
distinguish Tab from Ctrl+I, and better modifier handling.

Related: #123

fix(render): prevent flicker on resize

Added sync() call after resize events to force full redraw
and prevent leftover artifacts from previous state.

Fixes #45

perf(buffer): optimize diff algorithm

Changed from naive O(w*h) comparison to row-based diffing
to skip unchanged rows entirely. 40% faster on large buffers.

Benchmarks: bench/buffer_bench.cr
```

## Lefthook Hooks

Lefthook runs automatically on `git commit` and `git push`.

### Pre-commit Hook

Runs on every commit:

```yaml
# .lefthook.yml
pre-commit:
  commands:
    format:
      run: bin/hace format:check
      # Fail if code not formatted

    ameba:
      run: bin/hace ameba
      # Fail on lint issues
```

### Pre-push Hook

Runs on `git push`:

```yaml
pre-push:
  commands:
    spec:
      run: bin/hace spec
      # Fail if tests fail
```

## Manual Hook Execution

```bash
# Run pre-commit hooks manually
lefthook run pre-commit

# Run all hooks
lefthook run pre-push

# Run specific hook
lefthook run pre-commit ameba
```

## Linting (Ameba)

### Run Linter

```bash
# Basic run
bin/hace ameba

# With auto-fix
bin/hace ameba:fix

# Specific file
bin/ameba src/termisu/buffer.cr

# Specific rule
bin/ameba --rule Documentation src/termisu/
```

### Common Ameba Issues

| Issue | Fix |
|-------|-----|
| `LineLength` | Break long lines |
| `Documentation` | Add public API docs |
| `Naming` | Use snake_case for methods |
| `RedundantBegin` | Remove unnecessary begin |

### Ameba Configuration (.ameba.yml)

```yaml
# Project-specific rules already configured
# Review before modifying

LineLength:
  Enabled: true
  Max: 120  # Termisu uses 120

Documentation:
  Enabled: true
```

## Formatting (Crystal tool format)

### Run Formatter

```bash
# Format all code
bin/hace format

# Check without modifying
bin/hace format:check

# Specific files
crystal tool format src/termisu/buffer.cr spec/termisu/buffer_spec.cr
```

### Format Rules

- 2 spaces indentation
- No trailing whitespace
- Blank line after `require`
- Consistent spacing around operators

## Testing

### Run Tests

```bash
# All tests
bin/hace spec

# Specific file
crystal spec spec/termisu/buffer_spec.cr

# Verbose output
crystal spec --verbose

# Error trace
crystal spec --error-trace

# Specific line
crystal spec spec/termisu/buffer_spec.cr:42
```

### Test Coverage

- Aim for > 80% coverage on new code
- Test edge cases (boundaries, nil inputs)
- Test async code with proper cleanup
- Test error paths (exceptions, EINTR)

## Quality Gates

### Before Pushing

1. **Format check passes**
   ```bash
   bin/hace format:check
   ```

2. **Linter passes**
   ```bash
   bin/hace ameba
   ```

3. **Tests pass**
   ```bash
   bin/hace spec
   ```

4. **No leftover debug code**
   - Remove `puts`/`pp` debugging
   - Remove commented-out code

5. **Commit message follows format**
   - Type(scope): subject
   - Imperative mood
   - Under 50 chars subject

### CI Checks

GitHub Actions runs:

```yaml
- crystal spec -v          # Tests
- crystal tool format --check  # Format
- bin/ameba --fail-level error  # Linting
```

## Troubleshooting

### Lefthook Not Running

```bash
# Install lefthook
brew install lefthook  # macOS
# or download from https://github.com/evilmartians/lefthook

# Install hooks
lefthook install
```

### Format Check Fails

```bash
# Auto-format
bin/hace format

# Then commit again
git add .
git commit -m "..."
```

### Ameba Issues

```bash
# See what's wrong
bin/hace ameba

# Auto-fix what's possible
bin/hace ameba:fix

# Manual fix for the rest
```

### Test Failure

```bash
# Run with error trace
crystal spec --error-trace

# Run specific test
crystal spec spec/termisu/buffer_spec.cr:27

# Check for flaky tests
bin/hace spec  # Run twice
```

## Quick Reference

| Command | Purpose |
|---------|---------|
| `bin/hace format` | Format code |
| `bin/hace format:check` | Check format without changes |
| `bin/hace ameba` | Run linter |
| `bin/hace ameba:fix` | Auto-fix lint issues |
| `bin/hace spec` | Run tests |
| `bin/hace all` | Format + lint + test (parallel) |
| `lefthook run pre-commit` | Run pre-commit hooks manually |

## Commit Workflow Summary

```bash
# 1. Make changes
# ... code changes ...

# 2. Stage files
git add src/termisu/buffer.cr

# 3. Pre-commit check (lefthook runs automatically)
git commit -m "feat(buffer): add clear_region method"
# → format:check runs
# → ameba runs
# → if fail: commit rejected, fix and retry

# 4. Push (pre-push hook runs)
git push
# → spec runs
# → if fail: push rejected
```

## Best Practices

1. **Commit frequently** - Small, focused commits
2. **Write good messages** - Future you will thank present you
3. **Let hooks fail** - They catch real issues
4. **Don't bypass hooks** - `git commit --no-verify` is dangerous
5. **Run all before PR** - Ensure CI will pass
6. **Fix formatting first** - Format before other changes
7. **Test locally** - Don't rely on CI for feedback
