import { describe, expect, it } from "bun:test";

import { Status } from "../src/constants";
import { loadNative, ptr } from "../src/native";
import { createStyleBuffer } from "../src/structs";
import { Termisu } from "../src/termisu";

function asNumber(value: number | bigint): number {
  return typeof value === "number" ? value : Number(value);
}

function readLastError(native: ReturnType<typeof loadNative>): string {
  const len = asNumber(native.symbols.termisu_last_error_length() as number | bigint);
  if (len <= 0) return "";

  const bytes = new Uint8Array(len + 1);
  native.symbols.termisu_last_error_copy(ptr(bytes), BigInt(bytes.length));
  const nul = bytes.indexOf(0);
  return new TextDecoder().decode(nul >= 0 ? bytes.subarray(0, nul) : bytes);
}

describe("FFI integration", () => {
  it("exposes ABI version through Termisu wrapper", () => {
    expect(Termisu.abiVersion()).toBe(1);
  });

  it("returns InvalidHandle and a readable error for destroy(0)", () => {
    const native = loadNative();
    native.symbols.termisu_clear_error();

    const status = asNumber(native.symbols.termisu_destroy(0n) as number | bigint);
    expect(status).toBe(Status.InvalidHandle);
    expect(readLastError(native)).toMatch(/Invalid handle/);
  });

  it("returns InvalidArgument for poll_event with null output pointer", () => {
    const native = loadNative();
    native.symbols.termisu_clear_error();

    const status = asNumber(native.symbols.termisu_poll_event(0n, 0, 0) as number | bigint);
    expect(status).toBe(Status.InvalidArgument);
    expect(readLastError(native)).toMatch(/out_event is null/);
  });

  it("returns InvalidHandle for set_cell on unknown handle", () => {
    const native = loadNative();
    native.symbols.termisu_clear_error();

    const style = createStyleBuffer();
    const codepoint = "A".codePointAt(0) ?? 65;
    const status = asNumber(
      native.symbols.termisu_set_cell(9999n, 0, 0, codepoint, ptr(new Uint8Array(style))) as
        | number
        | bigint
    );

    expect(status).toBe(Status.InvalidHandle);
    expect(readLastError(native)).toMatch(/Invalid handle/);
  });
});
