# Termisu JS Runtime and FFI Architecture

Last verified: 2026-02-28

This document captures the target package architecture for JS bindings and how it maps to the Crystal core and native artifacts.

## Goals

- Keep rendering, input parsing, Unicode width, and terminal-mode semantics in Crystal.
- Make `bun add @termisu/*` work without manual native path wiring.
- Keep behavior consistent across Linux, macOS, and BSD targets.
- Isolate platform differences to native artifact loading and capability reporting.

## Non-Goals

- Reimplementing core terminal semantics in TypeScript.
- Framework-specific behavior differences at the runtime/core layer.

## Ground Truth From Crystal

Platform behavior is compile-time selected in Crystal and already abstracted behind stable APIs.

- `Poller.create` selects `Linux`, `Kqueue`, or `Poll` backend.
- Linux uses `epoll + timerfd`.
- Darwin/FreeBSD/OpenBSD uses `kqueue` timers.
- Fallback `poll` path handles ABI-specific `nfds_t` differences.
- TTY and terminal-size ioctl handling have platform branches.
- FFI exports include ABI version and layout signature checks.

These differences belong in native code, not in JS behavior logic.

## Package Topology

```mermaid
flowchart TD
  subgraph App
    APP[User app]
  end

  subgraph JS
    FW[@termisu/framework adapters]
    REC[@termisu/reconciler]
    RT[@termisu/runtime]
    CORE[@termisu/core]
    PLAT[@termisu/platform]
    CLI[@termisu/create-tui]
    START[@termisu/*-starter]
  end

  subgraph NativePkgs
    N1[@termisu/native-linux-x64-gnu]
    N2[@termisu/native-linux-arm64-gnu]
    N3[@termisu/native-linux-x64-musl]
    N4[@termisu/native-linux-arm64-musl]
    N5[@termisu/native-darwin-x64]
    N6[@termisu/native-darwin-arm64]
    N7[@termisu/native-freebsd-x64]
    N8[@termisu/native-freebsd-arm64]
  end

  subgraph NativeLib
    SO[libtermisu.so or libtermisu.dylib]
  end

  APP --> FW
  FW --> REC
  REC --> RT
  RT --> PLAT
  RT --> CORE
  CORE --> SO

  PLAT -. resolves target package .-> N1
  PLAT -. resolves target package .-> N2
  PLAT -. resolves target package .-> N3
  PLAT -. resolves target package .-> N4
  PLAT -. resolves target package .-> N5
  PLAT -. resolves target package .-> N6
  PLAT -. resolves target package .-> N7
  PLAT -. resolves target package .-> N8

  CLI --> START
```

## Runtime Startup Contract

```mermaid
sequenceDiagram
  participant App
  participant Runtime as @termisu/runtime
  participant Platform as @termisu/platform
  participant Core as @termisu/core
  participant Native as libtermisu

  App->>Runtime: createRuntime(options)
  Runtime->>Platform: detectTarget()/resolve library path
  Platform-->>Runtime: absolute path to native library
  Runtime->>Core: new Termisu({ libraryPath })
  Core->>Native: dlopen(symbols)
  Core->>Native: termisu_abi_version()
  Core->>Native: termisu_layout_signature()
  Native-->>Core: ABI + layout signature
  Core-->>Runtime: initialized handle
  Runtime-->>App: runtime/session ready
```

## Library Path Resolution

Resolution precedence should be deterministic:

1. explicit `libraryPath` option
2. `TERMISU_LIB_PATH`
3. platform resolver mapping (`os/arch/libc` -> native package -> bundled path)
4. actionable error with target and checked paths

```mermaid
flowchart TD
  S[loadNative start] --> E{libraryPath option?}
  E -- yes --> P1[resolve explicit path]
  E -- no --> V{TERMISU_LIB_PATH set?}
  V -- yes --> P2[resolve env path]
  V -- no --> M[platform detection and package mapping]
  M --> P3[resolve bundled native path]
  P1 --> X{exists and loadable?}
  P2 --> X
  P3 --> X
  X -- yes --> ABI[ABI/layout validation]
  ABI --> OK[return NativeLibrary]
  X -- no --> ERR[throw target-specific install error]
```

## Responsibility Matrix

| Package | Owns | Must not own |
| --- | --- | --- |
| `@termisu/platform` | target detection, native package mapping, path resolution | terminal behavior semantics |
| `@termisu/core` | FFI symbol binding, ABI/layout validation, native call wrappers | platform policy |
| `@termisu/runtime` | lifecycle orchestration and default wiring | native symbol definitions |
| `@termisu/reconciler` | state/tree to runtime operation mapping | dynamic library loading |
| `@termisu/framework/*` | framework adapter APIs | runtime internals |
| `@termisu/create-tui` + starters | scaffolding workflows/templates | runtime/core behavior |

## Capability Model

Runtime should consume one capability snapshot at startup.

Suggested fields:
- `platform` (`linux`, `darwin`, `freebsd`, ...)
- `poller_backend` (`linux`, `kqueue`, `poll`)
- `feature_bits` (mouse, enhanced keyboard, system timer, etc.)

Behavior contract:
- unsupported capabilities are exposed as `off` flags
- API semantics do not drift by platform

## Current Implementation Notes

- `@termisu/core` already validates ABI and struct layout signature.
- `@termisu/platform` currently detects `os/arch` and maps to package names.
- `@termisu/runtime` and framework packages are still scaffolds and need execution wiring.
- native packages currently expose manifest metadata and need artifact payload/release wiring.

## Source Anchors

- [src/termisu/event/poller.cr](/home/omar/sandbox/crystal/termisu/src/termisu/event/poller.cr)
- [src/termisu/event/poller/linux.cr](/home/omar/sandbox/crystal/termisu/src/termisu/event/poller/linux.cr)
- [src/termisu/event/poller/kqueue.cr](/home/omar/sandbox/crystal/termisu/src/termisu/event/poller/kqueue.cr)
- [src/termisu/event/poller/poll.cr](/home/omar/sandbox/crystal/termisu/src/termisu/event/poller/poll.cr)
- [src/termisu/tty.cr](/home/omar/sandbox/crystal/termisu/src/termisu/tty.cr)
- [src/termisu/terminal/backend.cr](/home/omar/sandbox/crystal/termisu/src/termisu/terminal/backend.cr)
- [src/termisu/ffi/exports.cr](/home/omar/sandbox/crystal/termisu/src/termisu/ffi/exports.cr)
- [src/termisu/ffi/layout.cr](/home/omar/sandbox/crystal/termisu/src/termisu/ffi/layout.cr)
- [javascript/core/src/native.ts](/home/omar/sandbox/crystal/termisu/javascript/core/src/native.ts)
- [javascript/core/src/termisu.ts](/home/omar/sandbox/crystal/termisu/javascript/core/src/termisu.ts)
- [javascript/platform/src/index.ts](/home/omar/sandbox/crystal/termisu/javascript/platform/src/index.ts)
- [javascript/runtime/src/index.ts](/home/omar/sandbox/crystal/termisu/javascript/runtime/src/index.ts)
