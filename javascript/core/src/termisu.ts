import { ptr } from "bun:ffi";

import { EventType, STRUCT, Status } from "./constants";
import { TermisuError } from "./errors";
import { loadNative, type NativeLibrary } from "./native";
import {
  createCellOpsBuffer,
  createSizeBuffer,
  readEventFrom,
  readSize,
  writeStyle,
} from "./structs";
import type { AnyEvent, CellOp, CellStyle, TermisuOptions } from "./types";

const ERROR_DECODER = new TextDecoder();

interface Scratch {
  view: DataView;
  pointer: number;
}

// The view retains the backing buffer, keeping the pointer valid for the
// lifetime of the scratch.
function createScratch(size: number): Scratch {
  const bytes = new Uint8Array(size);
  return { view: new DataView(bytes.buffer), pointer: ptr(bytes) };
}

function asBigInt(value: number | bigint): bigint {
  return typeof value === "bigint" ? value : BigInt(value);
}

function asNumber(value: number | bigint): number {
  return typeof value === "number" ? value : Number(value);
}

function firstCodepoint(input: string): number {
  const codepoint = input.codePointAt(0);
  if (codepoint === undefined) {
    throw new Error("Character must not be empty");
  }
  return codepoint;
}

export class Termisu {
  private readonly native: NativeLibrary;
  private handle: bigint;

  // Reused marshalling scratch, created on first use: JS is single-threaded
  // and each native call consumes the buffer before returning, so the bytes
  // are rewritten in place instead of allocated (and ptr-registered) per call.
  private styleScratch: Scratch | null = null;
  private eventScratch: Scratch | null = null;

  constructor(options: TermisuOptions = {}) {
    this.native = loadNative(options.libraryPath);
    const raw = this.native.symbols.termisu_create(options.syncUpdates === false ? 0 : 1);
    this.handle = asBigInt(raw as number | bigint);

    if (this.handle === 0n) {
      throw new TermisuError(
        Status.Error,
        this.getLastError() || "failed to create Termisu",
        "termisu_create"
      );
    }
  }

  static abiVersion(options: Pick<TermisuOptions, "libraryPath"> = {}): number {
    const native = loadNative(options.libraryPath);
    return asNumber(native.symbols.termisu_abi_version() as number | bigint);
  }

  destroy(): void {
    if (this.handle === 0n) return;
    const status = asNumber(this.native.symbols.termisu_destroy(this.handle) as number | bigint);
    this.assertStatus(status, "termisu_destroy");
    this.handle = 0n;
  }

  close(): void {
    this.assertAlive();
    const status = asNumber(this.native.symbols.termisu_close(this.handle) as number | bigint);
    this.assertStatus(status, "termisu_close");
  }

  size() {
    this.assertAlive();
    const buffer = createSizeBuffer();
    const status = asNumber(
      this.native.symbols.termisu_size(this.handle, ptr(new Uint8Array(buffer))) as number | bigint
    );
    this.assertStatus(status, "termisu_size");
    return readSize(buffer);
  }

  setSyncUpdates(enabled: boolean): void {
    this.assertAlive();
    const status = asNumber(
      this.native.symbols.termisu_set_sync_updates(this.handle, enabled ? 1 : 0) as number | bigint
    );
    this.assertStatus(status, "termisu_set_sync_updates");
  }

  syncUpdates(): boolean {
    this.assertAlive();
    const value = asNumber(
      this.native.symbols.termisu_sync_updates(this.handle) as number | bigint
    );
    return value !== 0;
  }

  clear(): void {
    this.callVoidStatus("termisu_clear");
  }

  render(): void {
    this.callVoidStatus("termisu_render");
  }

  sync(): void {
    this.callVoidStatus("termisu_sync");
  }

  setCursor(x: number, y: number): void {
    this.assertAlive();
    const status = asNumber(
      this.native.symbols.termisu_set_cursor(this.handle, x, y) as number | bigint
    );
    this.assertStatus(status, "termisu_set_cursor");
  }

  hideCursor(): void {
    this.callVoidStatus("termisu_hide_cursor");
  }

  showCursor(): void {
    this.callVoidStatus("termisu_show_cursor");
  }

  setCell(x: number, y: number, char: string | number, style?: CellStyle): void {
    this.assertAlive();

    const codepoint = typeof char === "number" ? char : firstCodepoint(char);
    let stylePtr = 0;
    if (style) {
      const scratch = this.ensureStyleScratch();
      writeStyle(scratch.view, style);
      stylePtr = scratch.pointer;
    }

    const status = asNumber(
      this.native.symbols.termisu_set_cell(this.handle, x, y, codepoint, stylePtr) as
        | number
        | bigint
    );
    this.assertStatus(status, "termisu_set_cell");
  }

  // Batched setCell: marshals all ops into one typed array and crosses the
  // FFI boundary once, instead of one native call (and guard + handle
  // lookup) per cell.
  setCells(ops: readonly CellOp[]): void {
    this.assertAlive();
    if (ops.length === 0) return;

    const buffer = createCellOpsBuffer(ops);
    const status = asNumber(
      this.native.symbols.termisu_set_cells(
        this.handle,
        ptr(new Uint8Array(buffer)),
        BigInt(ops.length)
      ) as number | bigint
    );
    this.assertStatus(status, "termisu_set_cells");
  }

  enableTimer(intervalMs: number): void {
    this.assertAlive();
    const status = asNumber(
      this.native.symbols.termisu_enable_timer_ms(this.handle, intervalMs) as number | bigint
    );
    this.assertStatus(status, "termisu_enable_timer_ms");
  }

  enableSystemTimer(intervalMs: number): void {
    this.assertAlive();
    const status = asNumber(
      this.native.symbols.termisu_enable_system_timer_ms(this.handle, intervalMs) as number | bigint
    );
    this.assertStatus(status, "termisu_enable_system_timer_ms");
  }

  disableTimer(): void {
    this.callVoidStatus("termisu_disable_timer");
  }

  enableMouse(): void {
    this.callVoidStatus("termisu_enable_mouse");
  }

  disableMouse(): void {
    this.callVoidStatus("termisu_disable_mouse");
  }

  enableEnhancedKeyboard(): void {
    this.callVoidStatus("termisu_enable_enhanced_keyboard");
  }

  disableEnhancedKeyboard(): void {
    this.callVoidStatus("termisu_disable_enhanced_keyboard");
  }

  pollEvent(timeoutMs: number = -1): AnyEvent | null {
    this.assertAlive();

    const scratch = this.ensureEventScratch();
    const status = asNumber(
      this.native.symbols.termisu_poll_event(this.handle, timeoutMs, scratch.pointer) as
        | number
        | bigint
    );

    if (status === Status.Timeout) {
      return null;
    }

    this.assertStatus(status, "termisu_poll_event");
    const event = readEventFrom(scratch.view);
    return event.type === EventType.None ? null : event;
  }

  getLastError(): string {
    const lenRaw = this.native.symbols.termisu_last_error_length() as number | bigint;
    const len = Number(asBigInt(lenRaw));
    if (len <= 0) return "";

    const bytes = new Uint8Array(len + 1);
    this.native.symbols.termisu_last_error_copy(ptr(bytes), BigInt(bytes.length));

    const firstNul = bytes.indexOf(0);
    const slice = firstNul >= 0 ? bytes.subarray(0, firstNul) : bytes;
    return ERROR_DECODER.decode(slice);
  }

  clearError(): void {
    this.native.symbols.termisu_clear_error();
  }

  private callVoidStatus(
    symbolName:
      | "termisu_clear"
      | "termisu_render"
      | "termisu_sync"
      | "termisu_hide_cursor"
      | "termisu_show_cursor"
      | "termisu_disable_timer"
      | "termisu_enable_mouse"
      | "termisu_disable_mouse"
      | "termisu_enable_enhanced_keyboard"
      | "termisu_disable_enhanced_keyboard"
  ): void {
    this.assertAlive();
    const status = asNumber(this.native.symbols[symbolName](this.handle) as number | bigint);
    this.assertStatus(status, symbolName);
  }

  private ensureStyleScratch(): Scratch {
    if (!this.styleScratch) {
      this.styleScratch = createScratch(STRUCT.cellStyle.size);
    }
    return this.styleScratch;
  }

  private ensureEventScratch(): Scratch {
    if (!this.eventScratch) {
      this.eventScratch = createScratch(STRUCT.event.size);
    }
    return this.eventScratch;
  }

  private assertAlive(): void {
    if (this.handle === 0n) {
      throw new TermisuError(Status.InvalidHandle, "Termisu handle is closed", "handle");
    }
  }

  private assertStatus(statusValue: number, action: string): void {
    const status = statusValue as Status;
    if (status === Status.Ok) {
      return;
    }

    const message = this.getLastError() || "native call failed";
    throw new TermisuError(status, message, action);
  }
}
