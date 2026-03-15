# AGENTS.md

Guidance for coding agents working in the Termisu repository.

## Scope

- This repo is primarily a Crystal library for terminal UIs.
- There are also Bun/TypeScript workspaces in `javascript/core` and `e2e`.
- Prefer changing the smallest surface area that solves the task.
- Follow existing architecture and naming before introducing new abstractions.
- Read `CLAUDE.md` first for architecture, command aliases, and project-specific patterns.
- Use `.claude/INDEX.md` as the directory for local skills, rules, and specialist agents.
- Check `PROJECT_INDEX.md` for a compact project overview.
- Look at `spec/` and `examples/` before inventing new APIs or behaviors.

## Instruction Files Present

- `CLAUDE.md` exists at the repo root and contains repo-specific guidance.
- `.claude/INDEX.md` and `.claude/rules/*.md` contain additional conventions worth following.
- No `.cursor/rules/` directory was found.
- No `.cursorrules` file was found.
- No `.github/copilot-instructions.md` file was found.

## Setup

```bash
shards install
shards build ameba
shards build hace
```

## Core Commands

```bash
# Crystal library
bin/hace spec
bin/hace format
bin/hace format:check
bin/hace ameba
bin/hace ameba:fix
bin/hace all

# Single Crystal spec file
crystal spec spec/termisu/buffer_spec.cr

# Single Crystal spec example by line number
crystal spec spec/termisu/buffer_spec.cr:149

# Single Crystal spec by example name
crystal spec spec/termisu/buffer_spec.cr --example "forces full re-render"

# Examples
bin/hace demo
bin/hace showcase
bin/hace animation
bin/hace colors
bin/hace kmd

# C ABI
bin/hace ffi:build
bin/hace c:test
bin/hace c:check

# JS / E2E
bun install
bin/hace js:typecheck
bin/hace js:test
bin/hace js:check
bin/hace e2e:test
bin/hace e2e:check

# Docs site
bin/hace docs:build
bin/hace docs:serve
```

## Single-Test Guidance

- For Crystal, prefer `crystal spec path/to/file_spec.cr` for a single file.
- To run one example, use `crystal spec path/to/file_spec.cr:<line>`.
- `--example` also works when the example name is stable.
- Crystal specs mirror `src/` structure under `spec/termisu/`.
- For Bun tests in `javascript/core`, run `bun test tests/path/to/file.test.ts` from `javascript/core`.
- For E2E tests, inspect the `e2e` workspace and run the narrowest supported `tui-test` target if the test runner accepts one; otherwise use the full `bin/hace e2e:test` command.

## Validation Order

- For Crystal-only changes: run `bin/hace format`, `bin/hace ameba`, then `bin/hace spec`.
- For JS workspace changes: run the relevant `bin/hace js:*` or `bin/hace e2e:*` commands.
- Before finishing a non-trivial change, prefer `bin/hace all` if the touched areas are covered by it.
- If you touch C ABI files, also run `bin/hace c:check` and `bin/hace c:test`.

## Repository Layout

- `src/termisu/` contains the main Crystal implementation.
- `src/termisu.cr` is the public entry point and requires the internal tree.
- `spec/termisu/` mirrors the `src/termisu/` structure.
- `spec/support/`, `spec/shared/`, and `examples/` are the best behavior references.
- `javascript/core/` contains Bun FFI bindings; `e2e/` contains terminal integration tests.

## Subsystem Maintainer Map

- The repo currently has a single primary maintainer: [omarluq](https://github.com/omarluq). Use the map below as routing guidance for where to look first, which files usually move together, and which changes deserve extra care before handing work back.
- Public Facade: maintainer `@omarluq`; start in `src/termisu.cr`, `src/termisu/terminal.cr`, and top-level public types such as `src/termisu/color.cr` and `src/termisu/attribute.cr`.
- Terminal State + Low-Level I/O: maintainer `@omarluq`; inspect `src/termisu/terminal/`, `src/termisu/tty.cr`, and `src/termisu/termios.cr` together because mode changes, cleanup, and fd ownership are tightly coupled.
- Rendering Core: maintainer `@omarluq`; changes usually span `src/termisu/buffer.cr`, `src/termisu/render_state.cr`, `src/termisu/cell.cr`, and cursor/color state.
- Input Reading: maintainer `@omarluq`; start with `src/termisu/reader.cr` and adjacent terminal backend code before changing buffering, blocking, or read-loop behavior.
- Input Parsing: maintainer `@omarluq`; focus on `src/termisu/input/parser.cr`, `src/termisu/input/key.cr`, and `src/termisu/input/modifier.cr`; confirm behavior against existing parser specs before changing escape handling.
- Event System: maintainer `@omarluq`; read `src/termisu/event/loop.cr`, `src/termisu/event.cr`, `src/termisu/event/source*.cr`, and event payload types as one subsystem.
- Poller Backends / Cross-Platform Timing: maintainer `@omarluq`; inspect `src/termisu/event/poller/`, `src/termisu/event/source/timer.cr`, and `src/termisu/event/source/system_timer.cr`; preserve platform branches and shutdown semantics.
- Terminfo + Capability Layer: maintainer `@omarluq`; start in `src/termisu/terminfo/`; parser, database lookup, builtins, and `tparm` logic should be treated as one compatibility surface.
- Logging: maintainer `@omarluq`; keep `src/termisu/log.cr` low-noise and best-effort, and avoid introducing logging that changes terminal timing or cleanup paths.
- FFI / C ABI: maintainer `@omarluq`; check `src/c/`, `include/`, and `spec/c/` together, then run the dedicated `bin/hace ffi:build`, `bin/hace c:check`, and `bin/hace c:test` commands when behavior changes.
- JavaScript/Bun Wrapper: maintainer `@omarluq`; use `javascript/core/` as the source of truth for Bun bindings and keep it aligned with the Crystal/C ABI surface.
- E2E / PTY Testing: maintainer `@omarluq`; inspect `e2e/` and related docs before changing terminal sequencing, async timing, or snapshot-style expectations.
- Examples: maintainer `@omarluq`; keep `examples/` representative of supported public APIs, especially when changing ergonomics or output behavior.
- Specs / Shared Test Infra: maintainer `@omarluq`; prefer mirrored specs under `spec/termisu/` and reuse helpers from `spec/support/` and `spec/shared/` before adding new scaffolding.
- Docs / Contributor Guidance: maintainer `@omarluq`; update `AGENTS.md`, `CLAUDE.md`, `PROJECT_INDEX.md`, `README.md`, `CONTRIBUTING.md`, and `docs/` or `docs-web/` when public behavior or contributor workflow changes.

## Code Style: Crystal

- Use 2 spaces; `.editorconfig` enforces this for `*.cr` files.
- Run `bin/hace format` instead of manual formatting.
- Keep lines ideally under 100 chars; 120 is the practical upper bound.
- Add a blank line after `require` statements.
- Prefer one top-level class/struct/module per file.
- Keep file paths aligned with namespaces, e.g. `src/termisu/event/source.cr` -> `Termisu::Event::Source`.

## Imports and File Organization

- Prefer relative `require` statements inside `src/termisu*`.
- Aggregator files commonly use glob requires such as `require "./termisu/*"`.
- Platform-specific code uses compile-time branches and conditional `require`s.
- Do not reorder requires gratuitously if file load order matters.

## Types and API Design

- Prefer explicit type annotations on public methods and important ivars.
- Use `Int32`, `UInt8`, `UInt64`, `Bool`, and `Time::Span` intentionally; match surrounding code.
- Use nilable types (`Foo?`) only when absence is a real state.
- Prefer value types (`struct`) for small immutable-ish data like cells, colors, cursors, or events.
- Use classes for resource-owning components like terminals, readers, and event sources.
- Return `Bool` for validation-style APIs when failure is expected and non-exceptional.
- Use keyword arguments for multi-argument APIs when they improve clarity.

## Naming Conventions

- Files use `snake_case.cr`.
- Types, enums, and modules use `PascalCase`.
- Methods and variables use `snake_case`.
- Predicate methods end in `?` and should return `Bool`.
- Setters end in `=`.
- Constants are usually `SCREAMING_SNAKE_CASE` in the current codebase.
- Keep all public types under the `Termisu::` namespace.

## Error Handling

- Use exceptions for true failure states and invalid system interactions.
- Reuse repo-specific errors like `Termisu::Error`, `Termisu::IOError`, and `Termisu::ParseError` when they fit.
- Preserve underlying context in error messages; include the failing operation.
- Use `ensure` for terminal cleanup, mode restoration, file closing, and similar lifecycle safety.
- Handle expected channel shutdowns explicitly, e.g. `rescue Channel::ClosedError` in event fibers.
- Avoid silent rescue unless the code is intentionally best-effort, like shutdown/log flushing.

## Concurrency and Terminal Patterns

- Event sources should use `Atomic(Bool)` or similar patterns for running state.
- Named fibers are preferred for long-lived background work.
- Check running state in loops so shutdown stays clean.
- Be careful with terminal mode transitions; restore state on every exit path.
- Rendering is diff-based and optimized; preserve buffer invariants when editing buffer logic.

## Testing Conventions

- Add or update specs with every behavioral change.
- Keep spec files colocated by mirrored path and name them `*_spec.cr`.
- Test public behavior first; add focused regression specs for bugs.
- Reuse helpers from `spec/support/` and shared patterns from `spec/shared/`.
- Use `MockRenderer` and other test doubles already present before adding new ones.

## Commit and Hook Awareness

- Pre-commit hooks are managed by Lefthook via `lefthook.yml`.
- Hooks run Crystal formatting/linting and relevant E2E formatting/linting.
- Update docs or examples when public behavior changes.

## Agent Workflow Tips

- Start with the narrowest relevant tests.
- Prefer existing patterns over novel abstractions.
- When touching low-level rendering, reader, termios, or event code, read adjacent files first.
- When unsure about intended API behavior, trust `examples/` and `spec/` over assumptions.
- If a task only affects `docs-web/`, also consult `docs-web/AGENTS.md`.

<!-- BEGIN BEADS INTEGRATION -->

## Issue Tracking with bd (beads)

**IMPORTANT**: This project uses **bd (beads)** for ALL issue tracking. Do NOT use markdown TODOs, task lists, or other tracking methods.

### Why bd?

- Dependency-aware: Track blockers and relationships between issues
- Git-friendly: Dolt-powered version control with native sync
- Agent-optimized: JSON output, ready work detection, discovered-from links
- Prevents duplicate tracking systems and confusion

### Quick Start

**Check for ready work:**

```bash
bd ready --json
```

**Create new issues:**

```bash
bd create "Issue title" --description="Detailed context" -t bug|feature|task -p 0-4 --json
bd create "Issue title" --description="What this issue is about" -p 1 --deps discovered-from:bd-123 --json
```

**Claim and update:**

```bash
bd update <id> --claim --json
bd update bd-42 --priority 1 --json
```

**Complete work:**

```bash
bd close bd-42 --reason "Completed" --json
```

### Issue Types

- `bug` - Something broken
- `feature` - New functionality
- `task` - Work item (tests, docs, refactoring)
- `epic` - Large feature with subtasks
- `chore` - Maintenance (dependencies, tooling)

### Priorities

- `0` - Critical (security, data loss, broken builds)
- `1` - High (major features, important bugs)
- `2` - Medium (default, nice-to-have)
- `3` - Low (polish, optimization)
- `4` - Backlog (future ideas)

### Workflow for AI Agents

1. **Check ready work**: `bd ready` shows unblocked issues
2. **Claim your task atomically**: `bd update <id> --claim`
3. **Work on it**: Implement, test, document
4. **Discover new work?** Create linked issue:
   - `bd create "Found bug" --description="Details about what was found" -p 1 --deps discovered-from:<parent-id>`
5. **Complete**: `bd close <id> --reason "Done"`

### Auto-Sync

bd automatically syncs via Dolt:

- Each write auto-commits to Dolt history
- Use `bd dolt push`/`bd dolt pull` for remote sync
- No manual export/import needed!

### Important Rules

- ✅ Use bd for ALL task tracking
- ✅ Always use `--json` flag for programmatic use
- ✅ Link discovered work with `discovered-from` dependencies
- ✅ Check `bd ready` before asking "what should I work on?"
- ❌ Do NOT create markdown TODO lists
- ❌ Do NOT use external issue trackers
- ❌ Do NOT duplicate tracking systems

For more details, see README.md and docs/QUICKSTART.md.

## Landing the Plane (Session Completion)

**When ending a work session**, you MUST complete ALL steps below. Work is NOT complete until `git push` succeeds.

**MANDATORY WORKFLOW:**

1. **File issues for remaining work** - Create issues for anything that needs follow-up
2. **Run quality gates** (if code changed) - Tests, linters, builds
3. **Update issue status** - Close finished work, update in-progress items
4. **PUSH TO REMOTE** - This is MANDATORY:

   ```bash
   git pull --rebase
   bd dolt push
   git push
   git status  # MUST show "up to date with origin"
   ```

5. **Clean up** - Clear stashes, prune remote branches
6. **Verify** - All changes committed AND pushed
7. **Hand off** - Provide context for next session

**CRITICAL RULES:**

- Work is NOT complete until `git push` succeeds
- NEVER stop before pushing - that leaves work stranded locally
- NEVER say "ready to push when you are" - YOU must push
- If push fails, resolve and retry until it succeeds

<!-- END BEADS INTEGRATION -->

Use 'bd' for task tracking

<!-- bv-agent-instructions-v2 -->

---

## Beads Workflow Integration

This repo uses [beads_viewer](https://github.com/Dicklesworthstone/beads_viewer) (`bv`) as a read-only sidecar for graph-aware triage on the existing beads data in `.beads/`.

### Using bv as an AI sidecar

bv is a graph-aware triage engine for Beads projects. Use it to inspect priorities, blockers, and dependency structure without replacing the repo's `bd` write/update workflow.

**Scope boundary:** use `bv` for read-only triage and graph analysis; use `bd` for creating, updating, claiming, and closing issues.

**CRITICAL: Use ONLY --robot-* flags with the repo database, e.g. `bv --db .beads --robot-triage`. Never run bare `bv`; it launches an interactive TUI that blocks your session.**

#### Recommended Commands

**`bv --db .beads --robot-triage` is the main entry point.** It returns a compact triage view with ranked recommendations, quick wins, blockers, project health, and suggested follow-up commands.

```bash
bv --db .beads --robot-triage
bv --db .beads --robot-next
bv --db .beads --robot-plan
bv --db .beads --robot-alerts
bv --db .beads --robot-suggest
bv --db .beads --robot-triage --format toon
```

Accurate dependencies and labels materially improve `bv` results, so keep issue links and metadata tidy through the normal `bd` workflow.

#### Other read-only views

- `quick_ref`: at-a-glance counts + top 3 picks
- `recommendations`: ranked actionable items with scores, reasons, unblock info
- `quick_wins`: low-effort high-impact items
- `blockers_to_clear`: items that unblock the most downstream work
- `project_health`: status/type/priority distributions, graph metrics
- `commands`: copy-paste shell commands for next steps

| Command | Returns |
|---------|---------|
| `--robot-plan` | Parallel execution tracks with unblocks lists |
| `--robot-priority` | Priority misalignment detection with confidence |
| `--robot-insights` | Full metrics: PageRank, betweenness, HITS, eigenvector, critical path, cycles, k-core |
| `--robot-alerts` | Stale issues, blocking cascades, priority mismatches |
| `--robot-suggest` | Hygiene: duplicates, missing deps, label suggestions, cycle breaks |
| `--robot-diff --diff-since <ref>` | Changes since ref: new/closed/modified issues |
| `--robot-graph [--graph-format=json\|dot\|mermaid]` | Dependency graph export |

#### Scoping & Filtering

```bash
bv --db .beads --robot-plan --label backend              # Scope to label's subgraph
bv --db .beads --robot-insights --as-of HEAD~30          # Historical point-in-time
bv --db .beads --recipe actionable --robot-plan          # Pre-filter: ready to work (no blockers)
bv --db .beads --recipe high-impact --robot-triage       # Pre-filter: top PageRank scores
```

<!-- end-bv-agent-instructions -->
