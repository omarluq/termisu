import assert from "node:assert/strict";

import { Status } from "../src/constants";
import { loadNative, ptr } from "../src/native";
import { createStyleBuffer } from "../src/structs";
import { Termisu } from "../src/termisu";

function toNumber(value: number | bigint): number {
  return typeof value === "number" ? value : Number(value);
}

function readLastError(native: ReturnType<typeof loadNative>): string {
  const len = toNumber(native.symbols.termisu_last_error_length() as number | bigint);
  if (len <= 0) return "";

  const bytes = new Uint8Array(len + 1);
  native.symbols.termisu_last_error_copy(ptr(bytes), BigInt(bytes.length));
  const nul = bytes.indexOf(0);
  return new TextDecoder().decode(nul >= 0 ? bytes.subarray(0, nul) : bytes);
}

function run(): void {
  assert.equal(Termisu.abiVersion(), 1);

  const native = loadNative();

  native.symbols.termisu_clear_error();
  assert.equal(
    toNumber(native.symbols.termisu_destroy(0n) as number | bigint),
    Status.InvalidHandle
  );
  assert.match(readLastError(native), /Invalid handle/);

  native.symbols.termisu_clear_error();
  assert.equal(
    toNumber(native.symbols.termisu_poll_event(0n, 0, 0) as number | bigint),
    Status.InvalidArgument
  );
  assert.match(readLastError(native), /out_event is null/);

  native.symbols.termisu_clear_error();
  const style = createStyleBuffer();
  const codepoint = "A".codePointAt(0);
  assert.notEqual(codepoint, undefined);
  assert.equal(
    toNumber(
      native.symbols.termisu_set_cell(9999n, 0, 0, codepoint ?? 65, ptr(new Uint8Array(style))) as
        | number
        | bigint
    ),
    Status.InvalidHandle
  );
  assert.match(readLastError(native), /Invalid handle/);

  console.log("TypeScript FFI tests passed");
}

run();
