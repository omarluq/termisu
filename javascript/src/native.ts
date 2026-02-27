import { dlopen, ptr, suffix } from "bun:ffi";
import { existsSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

import { ABI_VERSION, STRUCT_LAYOUT_SIGNATURE } from "./constants";

const SYMBOLS = {
  termisu_abi_version: { args: [], returns: "u32" },
  termisu_layout_signature: { args: [], returns: "u64" },
  termisu_create: { args: ["u8"], returns: "u64" },
  termisu_destroy: { args: ["u64"], returns: "i32" },
  termisu_close: { args: ["u64"], returns: "i32" },

  termisu_size: { args: ["u64", "ptr"], returns: "i32" },
  termisu_set_sync_updates: { args: ["u64", "u8"], returns: "i32" },
  termisu_sync_updates: { args: ["u64"], returns: "u8" },

  termisu_clear: { args: ["u64"], returns: "i32" },
  termisu_render: { args: ["u64"], returns: "i32" },
  termisu_sync: { args: ["u64"], returns: "i32" },
  termisu_set_cursor: { args: ["u64", "i32", "i32"], returns: "i32" },
  termisu_hide_cursor: { args: ["u64"], returns: "i32" },
  termisu_show_cursor: { args: ["u64"], returns: "i32" },
  termisu_set_cell: { args: ["u64", "i32", "i32", "u32", "ptr"], returns: "i32" },

  termisu_enable_timer_ms: { args: ["u64", "i32"], returns: "i32" },
  termisu_enable_system_timer_ms: { args: ["u64", "i32"], returns: "i32" },
  termisu_disable_timer: { args: ["u64"], returns: "i32" },
  termisu_enable_mouse: { args: ["u64"], returns: "i32" },
  termisu_disable_mouse: { args: ["u64"], returns: "i32" },
  termisu_enable_enhanced_keyboard: { args: ["u64"], returns: "i32" },
  termisu_disable_enhanced_keyboard: { args: ["u64"], returns: "i32" },
  termisu_poll_event: { args: ["u64", "i32", "ptr"], returns: "i32" },

  termisu_last_error_length: { args: [], returns: "u64" },
  termisu_last_error_copy: { args: ["ptr", "u64"], returns: "u64" },
  termisu_clear_error: { args: [], returns: "void" },
} as const;

type SymbolMap = {
  [K in keyof typeof SYMBOLS]: (...args: Array<number | bigint>) => number | bigint | undefined;
};

export interface NativeLibrary {
  symbols: SymbolMap;
  close(): void;
  path: string;
}

function asNumber(value: number | bigint | undefined): number {
  if (value === undefined) {
    throw new Error("Native symbol returned undefined");
  }
  return typeof value === "number" ? value : Number(value);
}

function asBigInt(value: number | bigint | undefined): bigint {
  if (value === undefined) {
    throw new Error("Native symbol returned undefined");
  }
  return typeof value === "bigint" ? value : BigInt(value);
}

function formatHex(value: bigint): string {
  return `0x${value.toString(16).padStart(16, "0")}`;
}

function validateNativeLayout(path: string, symbols: SymbolMap): void {
  const abiVersion = asNumber(symbols.termisu_abi_version());
  if (abiVersion !== ABI_VERSION) {
    throw new Error(
      [
        `Unsupported Termisu ABI version from ${path}.`,
        `Expected ${ABI_VERSION}, got ${abiVersion}.`,
      ].join(" ")
    );
  }

  const nativeSignature = asBigInt(symbols.termisu_layout_signature());
  if (nativeSignature !== STRUCT_LAYOUT_SIGNATURE) {
    throw new Error(
      [
        `Native struct layout mismatch for ${path}.`,
        `Expected ${formatHex(STRUCT_LAYOUT_SIGNATURE)}, got ${formatHex(nativeSignature)}.`,
        "Rebuild native library and JS bindings from the same revision.",
      ].join(" ")
    );
  }
}

function resolveLibraryPath(explicit?: string): string {
  if (explicit) return resolve(explicit);

  const envPath = process.env.TERMISU_LIB_PATH;
  if (envPath) return resolve(envPath);

  const moduleDir = dirname(fileURLToPath(import.meta.url));
  const candidates = [
    resolve(join(process.cwd(), "bin", `libtermisu.${suffix}`)),
    resolve(join(process.cwd(), "..", "bin", `libtermisu.${suffix}`)),
    resolve(join(moduleDir, "..", "..", "bin", `libtermisu.${suffix}`)),
  ];

  for (const candidate of candidates) {
    if (existsSync(candidate)) return candidate;
  }

  throw new Error(
    [
      "Could not locate Termisu native library.",
      "Set TERMISU_LIB_PATH or pass { libraryPath }.",
      `Checked: ${candidates.join(", ")}`,
    ].join(" ")
  );
}

const cache = new Map<string, NativeLibrary>();

export function loadNative(explicitPath?: string): NativeLibrary {
  const path = resolveLibraryPath(explicitPath);
  const cached = cache.get(path);
  if (cached) return cached;

  const loaded = dlopen(path, SYMBOLS);
  validateNativeLayout(path, loaded.symbols as unknown as SymbolMap);

  const close = () => {
    loaded.close();
    cache.delete(path);
  };

  const native: NativeLibrary = {
    symbols: loaded.symbols as unknown as SymbolMap,
    close,
    path,
  };

  cache.set(path, native);
  return native;
}

export { ptr };
