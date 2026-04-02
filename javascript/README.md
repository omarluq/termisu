# Termisu JavaScript Workspace

This workspace is intentionally small.

The current JavaScript surface focuses on a minimal Bun FFI layer plus
platform-specific native package scaffolding.

| Package | Path | Purpose |
| --- | --- | --- |
| `@termisu/core` | `javascript/core` | Public Bun FFI bindings and JS API |
| `@termisu/platform` | `javascript/platform` | Internal target detection and native package mapping |
| `@termisu/native-*` | `javascript/native/**` | Platform-specific native package metadata |

## Current Status

- `@termisu/core` is the only intended user-facing JS package today.
- `@termisu/platform` is an internal helper package.
- Native packages are scaffolds for platform delivery and release wiring.
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
