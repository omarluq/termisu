import { describe, expect, it } from "bun:test";
import { resolve } from "node:path";

import { ABI_VERSION } from "../src/constants";
import { loadNative } from "../src/native";

function asNumber(value: number | bigint | undefined): number {
  if (value === undefined) {
    throw new Error("native symbol returned undefined");
  }
  return typeof value === "number" ? value : Number(value);
}

describe("native loader", () => {
  it("loads and caches native libraries by path", () => {
    const explicitPath = process.env.TERMISU_LIB_PATH;
    const a = loadNative(explicitPath);
    const b = loadNative(explicitPath);

    expect(a).toBe(b);
    if (explicitPath) {
      expect(a.path).toBe(resolve(explicitPath));
    }
  });

  it("evicts cache entry when close is called", () => {
    const explicitPath = process.env.TERMISU_LIB_PATH;
    const first = loadNative(explicitPath);
    first.close();

    const second = loadNative(explicitPath);
    expect(second).not.toBe(first);
    second.close();
  });

  it("exposes expected ABI and non-zero layout signature", () => {
    const native = loadNative(process.env.TERMISU_LIB_PATH);
    expect(asNumber(native.symbols.termisu_abi_version())).toBe(ABI_VERSION);

    const signature = native.symbols.termisu_layout_signature();
    const signatureBigint = typeof signature === "bigint" ? signature : BigInt(signature ?? 0);
    expect(signatureBigint > 0n).toBe(true);
  });
});
