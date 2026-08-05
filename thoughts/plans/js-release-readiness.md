# JS Release Readiness Plan

## Goal

Get the kept JS packages to an initial-release state where `@termisu/core` is publishable, native target packages are real delivery artifacts, and install/runtime behavior is validated on the CI-tested platforms.

## Current Package Roles

### Public package

- `javascript/core` → `@termisu/core`

### Published internal packages

- `javascript/native/darwin/arm64` → `@termisu/native-darwin-arm64`
- `javascript/native/darwin/x64` → `@termisu/native-darwin-x64`
- `javascript/native/freebsd/arm64` → `@termisu/native-freebsd-arm64`
- `javascript/native/freebsd/x64` → `@termisu/native-freebsd-x64`
- `javascript/native/linux/arm64/gnu` → `@termisu/native-linux-arm64-gnu`
- `javascript/native/linux/arm64/musl` → `@termisu/native-linux-arm64-musl`
- `javascript/native/linux/x64/gnu` → `@termisu/native-linux-x64-gnu`
- `javascript/native/linux/x64/musl` → `@termisu/native-linux-x64-musl`

## Current State

- `@termisu/core` resolves native libraries in this order:
  1. explicit `libraryPath`
  2. `TERMISU_LIB_PATH`
  3. installed native package manifest lookup
  4. repo-local `bin/` fallback
- `@termisu/core` carries native packages as optional dependencies and owns target detection for Linux glibc vs musl, Darwin, and FreeBSD.
- CI validates JS lint/format/typecheck/tests and Crystal/C ABI builds, but native npm package publication is not wired yet.
- `publish-core.yml` publishes only `@termisu/core`.
- Native packages currently look like metadata/package shells and still need actual binary payload wiring.

## Release Gaps

### 1. Native package contents are not fully defined

Open decisions:

- exact binary filename per OS (`.so` vs `.dylib`)
- exact package layout (`libtermisu.*` at package root vs `bin/libtermisu.*`)
- whether `manifest.json` should also record the shipped relative binary path

### 2. Native package build/publish flow is missing

Current workflows build a shared library into repo-local `bin/`, but do not:

- copy that binary into each native package
- verify each native package packs correctly
- publish native packages before `@termisu/core`

### 3. Installed-package runtime behavior needs pack/install validation

Current tests cover resolution logic, but not the real post-pack install shape for:

- `bun add @termisu/core`
- installed optional native package layout
- `import.meta.resolve("@termisu/native-*/manifest")` from a packed install

### 4. Release orchestration is incomplete

Needed but not yet present:

- version sync between `@termisu/core` and native packages
- publish order / dependency order
- dist-tag strategy across all JS packages
- provenance/public access for the full release set

## Implementation Checklist

### Phase 1: Lock package layout

- [ ] Choose final native binary location inside each native package
- [ ] Add binary-path field to `manifest.json` if needed
- [ ] Update `javascript/core/src/native.ts` to match the final layout exactly
- [ ] Document the package layout in `javascript/README.md`

### Phase 2: Build real native package artifacts

- [ ] Add a packaging script that copies built shared libraries into each native package
- [ ] Ensure Linux packages receive the correct `.so` payload per target
- [ ] Ensure macOS packages receive the correct `.dylib` payload per target
- [ ] Decide whether FreeBSD native packages ship initially or remain deferred
- [ ] Verify package `files`/`exports` include the binary payload and manifest

### Phase 3: Add pack/install verification

- [ ] Add a smoke check for `bun pm pack` or equivalent on `javascript/core`
- [ ] Add the same smoke check for each native package
- [ ] Add an install test that simulates `@termisu/core` + matching native package resolution
- [ ] Verify missing optional native packages fail with actionable errors

### Phase 4: Release workflow

- [ ] Create a native-package publish workflow
- [ ] Publish native packages before `@termisu/core`
- [ ] Ensure `@termisu/core` version matches native package versions
- [ ] Add prerelease/stable dist-tag rules for the native packages too
- [ ] Add a release checklist doc for JS packages

### Phase 5: Release scope decision

- [ ] Decide the initial supported npm release matrix
- [ ] Prefer a smaller first release if artifact generation is not ready for all targets
- [ ] Mark unsupported/deferred targets clearly in docs and workflow config

## Recommended Initial Release Scope

Safest first release candidates:

- Linux x64 GNU
- Linux arm64 GNU
- Darwin arm64
- Darwin x64

Optional defer candidates until artifact production is proven:

- Linux musl targets
- FreeBSD targets

## Validation Targets

Before the first npm release, these should pass in CI:

- JS checks: `bun run js:check`
- E2E checks: `bun run e2e:check`
- C ABI workflow: `.github/workflows/ffi-bindings.yml`
- package pack/install smoke checks for `@termisu/core` and native packages

## Suggested Task Order

1. Finalize native package binary layout.
2. Add scripts to materialize binaries into native packages.
3. Add pack/install verification.
4. Add native-package publish workflow.
5. Narrow or confirm the initial platform release matrix.
