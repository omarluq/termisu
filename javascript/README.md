# @termisu/core

TypeScript bindings for Termisu using `bun:ffi`.

## Requirements

- Bun `>= 1.3`
- Built Termisu shared library:
  - Linux: `libtermisu.so`
  - macOS: `libtermisu.dylib`
  - Windows: not supported

Build native lib from the repository root:

```bash
bin/hace ffi:build
```

By default, this package looks for `./bin/libtermisu.<ext>` from the current working directory.
You can override with `TERMISU_LIB_PATH=/absolute/path/to/library`.

## Install

```bash
bun install
```

## Build

```bash
bun run build
```

## Typecheck

```bash
bun run typecheck
```

## Quick Example

```ts
import { Attribute, Color, Termisu } from "@termisu/core";

const termisu = new Termisu({ syncUpdates: true });

try {
  termisu.setCell(0, 0, "H", { fg: Color.green, attr: Attribute.Bold });
  termisu.setCell(1, 0, "i", { fg: Color.bright_cyan });
  termisu.render();
} finally {
  termisu.destroy();
}
```

## Development Demo

```bash
bun run dev
```
