# JS Example E2E Parity Plan

## Goal

Get JS examples to the point where the E2E harness can run them with comparable coverage to the Crystal examples on the CI-tested platforms.

## Current State

- Current E2E workflow builds Crystal example binaries only via `.github/actions/build-e2e-binaries/action.yml`.
- `@termisu/core` now owns native target detection directly, so JS example launch wiring only needs `@termisu/core` plus the native packages.
- Current E2E tests target these Crystal binaries:
  - `bin/showcase`
  - `bin/simple`
  - `bin/colors`
  - `bin/kmd`
  - `bin/animation`
- `javascript/core/examples/basic.ts` exists, but there is no JS example build/launch pipeline wired into E2E.
- `ffi-bindings.yml` already builds the shared library and runs `bun run js:test`, which is a useful foundation for JS example execution.

## E2E Parity Gaps

### 1. Example surface mismatch

Crystal examples with E2E coverage:

- simple
- showcase
- colors
- keyboard/mouse demo
- animation

JS examples currently present:

- basic only

### 2. No JS example launcher contract

The E2E harness expects an executable program path under `bin/`.

Needed decisions:

- whether JS examples are launched through Bun directly
- or wrapped as generated `bin/*` launch scripts
- how native library path is injected at runtime during E2E

### 3. No JS-specific E2E matrix in CI

Current E2E workflow validates:

- OS: Linux + macOS
- shells: bash, zsh, fish
- Crystal versions: 1.17.0 / 1.18.2 / 1.19.1

No job currently runs JS examples under the same harness.

## Proposed Example Parity Map

### Phase 1: minimal parity

- [ ] JS simple example matching the Crystal `simple` behavior
- [ ] JS colors example matching the Crystal `colors` behavior
- [ ] JS showcase example matching the Crystal `showcase` behavior

### Phase 2: interactive parity

- [ ] JS keyboard/mouse demo matching `keyboard_and_mouse.cr`
- [ ] JS animation example matching `animation.cr`

## Implementation Checklist

### Phase 1: establish JS example runner shape

- [ ] Decide executable contract for JS examples in E2E
- [ ] Add a build or wrapper step that produces stable `bin/js-*` entrypoints
- [ ] Ensure each JS example can locate the native library in CI
- [ ] Keep launch semantics shell-safe for bash/zsh/fish jobs

### Phase 2: add the first JS examples

- [ ] Add `javascript/core/examples/simple.ts`
- [ ] Add `javascript/core/examples/colors.ts`
- [ ] Add `javascript/core/examples/showcase.ts`
- [ ] Match visible text and lifecycle behavior closely enough for tui-test assertions

### Phase 3: add JS E2E tests

- [ ] Create JS versions of the current E2E specs or parameterize the existing ones
- [ ] Reuse existing assertions where output is intentionally equivalent
- [ ] Add JS-specific snapshots only where parity is intentionally approximate

### Phase 4: CI integration

- [ ] Extend `.github/actions/build-e2e-binaries/action.yml` or add a sibling action for JS example runners
- [ ] Add JS example artifacts to `.github/workflows/e2e.yml`
- [ ] Run JS E2E on the same OS/shell matrix as Crystal where practical
- [ ] Upload JS traces/snapshots on failure

### Phase 5: parity expansion

- [ ] Add JS keyboard/mouse example + E2E tests
- [ ] Add JS animation example + E2E tests
- [ ] Compare expected drift between Crystal and JS implementations explicitly

## Suggested Task Breakdown

### Track A: Example implementation

- [ ] Port `simple`
- [ ] Port `colors`
- [ ] Port `showcase`
- [ ] Port `keyboard_and_mouse`
- [ ] Port `animation`

### Track B: Runner/build plumbing

- [ ] Produce stable JS executables or wrappers under `bin/`
- [ ] Inject `TERMISU_LIB_PATH` in a reproducible way for JS E2E
- [ ] Verify Bun is available everywhere JS E2E runs

### Track C: Test harness

- [ ] Decide shared vs duplicated spec files
- [ ] Introduce helpers for selecting Crystal vs JS program targets
- [ ] Keep snapshots isolated per implementation if output diverges slightly

## Recommended First Milestone

Ship one JS E2E vertical slice before chasing full parity:

- `simple.ts`
- one JS-specific E2E spec based on `e2e/tests/simple.test.ts`
- one CI job that builds native lib + runs the JS simple example under tui-test

Once that works on Linux and macOS, expand to `colors` and `showcase`.

## Validation Targets

For the first parity milestone:

- [ ] `bun run js:check`
- [ ] `bun run e2e:check`
- [ ] local JS example launch with shared library available
- [ ] CI JS example E2E on Linux + macOS
