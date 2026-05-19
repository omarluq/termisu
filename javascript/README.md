# Termisu JavaScript Workspace

This workspace is intentionally small.

The current JavaScript surface focuses on a minimal Bun FFI layer plus
platform-specific native package scaffolding.

| Package | Path | Purpose |
| --- | --- | --- |
| `@termisu/core` | `javascript/core` | Public Bun FFI bindings, native target detection, and JS API |
| `@termisu/native-*` | `javascript/native/**` | Platform-specific native package metadata |

## Current Status

- `@termisu/core` is the only intended user-facing JS package today.
- `@termisu/core` declares platform-specific native packages as optional
  dependencies so one install command can resolve the right target.
- Native packages are still scaffolds for platform delivery and release wiring.
- Framework adapters, starters, and CLI scaffolding were removed until the core
  JS distribution story is fully working.

## Supported Native Targets

- Linux x64 GNU
- Linux arm64 GNU
- Linux x64 musl
- Linux arm64 musl
- Darwin x64
- Darwin arm64
- FreeBSD x64
- FreeBSD arm64

## Development

From the repository root:

```bash
bun run js:typecheck
bun run e2e:typecheck
```
