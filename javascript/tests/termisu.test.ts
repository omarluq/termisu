import { describe, expect, it } from "bun:test";

import { Attribute, attrs } from "../src/attribute";
import { Color } from "../src/color";
import { Status } from "../src/constants";
import { TermisuError } from "../src/errors";
import { Termisu } from "../src/termisu";

type NativeValue = number | bigint | undefined;
type SymbolFn = (...args: Array<number | bigint>) => NativeValue;

type TestTermisu = {
  size(): { width: number; height: number };
  clear(): void;
  render(): void;
  sync(): void;
  setSyncUpdates(enabled: boolean): void;
  syncUpdates(): boolean;
  setCell(x: number, y: number, char: string | number, style?: unknown): void;
  setCursor(x: number, y: number): void;
  hideCursor(): void;
  showCursor(): void;
  enableTimer(intervalMs: number): void;
  enableSystemTimer(intervalMs: number): void;
  disableTimer(): void;
  enableMouse(): void;
  disableMouse(): void;
  enableEnhancedKeyboard(): void;
  disableEnhancedKeyboard(): void;
  pollEvent(timeoutMs?: number): unknown;
  close(): void;
  destroy(): void;
  clearError(): void;
  native: {
    symbols: Record<string, SymbolFn>;
    close: () => void;
    path: string;
  };
  handle: bigint;
  getLastError: () => string;
};

interface MockTermisu {
  termisu: TestTermisu;
  calls: Array<{ name: string; args: Array<number | bigint> }>;
}

function buildMockTermisu(
  overrides: Partial<Record<string, SymbolFn>> = {},
  startHandle: bigint = 1n
): MockTermisu {
  const calls: Array<{ name: string; args: Array<number | bigint> }> = [];
  const base: Record<string, SymbolFn> = {
    termisu_destroy: () => Status.Ok,
    termisu_close: () => Status.Ok,
    termisu_size: () => Status.Ok,
    termisu_set_sync_updates: () => Status.Ok,
    termisu_sync_updates: () => 1,
    termisu_clear: () => Status.Ok,
    termisu_render: () => Status.Ok,
    termisu_sync: () => Status.Ok,
    termisu_set_cursor: () => Status.Ok,
    termisu_hide_cursor: () => Status.Ok,
    termisu_show_cursor: () => Status.Ok,
    termisu_set_cell: () => Status.Ok,
    termisu_enable_timer_ms: () => Status.Ok,
    termisu_enable_system_timer_ms: () => Status.Ok,
    termisu_disable_timer: () => Status.Ok,
    termisu_enable_mouse: () => Status.Ok,
    termisu_disable_mouse: () => Status.Ok,
    termisu_enable_enhanced_keyboard: () => Status.Ok,
    termisu_disable_enhanced_keyboard: () => Status.Ok,
    termisu_poll_event: () => Status.Ok,
    termisu_last_error_length: () => 0n,
    termisu_last_error_copy: () => 0n,
    termisu_clear_error: () => undefined,
  };

  const symbols: Record<string, SymbolFn> = {};
  for (const [name, impl] of Object.entries(base)) {
    symbols[name] = (...args: Array<number | bigint>) => {
      calls.push({ name, args });
      const override = overrides[name];
      return (override ?? impl)(...args);
    };
  }

  const termisu = Object.create(Termisu.prototype) as unknown as TestTermisu;
  termisu.native = { symbols, close: () => undefined, path: "mock" };
  termisu.handle = startHandle;
  termisu.getLastError = () => "mock native failure";

  return { termisu, calls };
}

describe("Termisu wrapper behavior", () => {
  it("routes lifecycle and render operations through native symbols", () => {
    const { termisu, calls } = buildMockTermisu();

    termisu.clear();
    termisu.render();
    termisu.sync();
    termisu.hideCursor();
    termisu.showCursor();
    termisu.enableMouse();
    termisu.disableMouse();
    termisu.enableEnhancedKeyboard();
    termisu.disableEnhancedKeyboard();
    termisu.close();

    const names = calls.map((entry) => entry.name);
    expect(names).toContain("termisu_clear");
    expect(names).toContain("termisu_render");
    expect(names).toContain("termisu_sync");
    expect(names).toContain("termisu_hide_cursor");
    expect(names).toContain("termisu_show_cursor");
    expect(names).toContain("termisu_enable_mouse");
    expect(names).toContain("termisu_disable_mouse");
    expect(names).toContain("termisu_enable_enhanced_keyboard");
    expect(names).toContain("termisu_disable_enhanced_keyboard");
    expect(names).toContain("termisu_close");
  });

  it("converts boolean sync update values and reads back bool state", () => {
    const { termisu, calls } = buildMockTermisu({
      termisu_sync_updates: () => 0,
    });

    termisu.setSyncUpdates(false);
    termisu.setSyncUpdates(true);

    const syncCalls = calls.filter((entry) => entry.name === "termisu_set_sync_updates");
    expect(syncCalls).toHaveLength(2);
    expect(syncCalls[0]?.args).toEqual([1n, 0]);
    expect(syncCalls[1]?.args).toEqual([1n, 1]);
    expect(termisu.syncUpdates()).toBe(false);
  });

  it("reads size and forwards cursor coordinates", () => {
    const { termisu, calls } = buildMockTermisu();

    expect(termisu.size()).toEqual({ width: 0, height: 0 });
    termisu.setCursor(12, 4);

    const sizeCall = calls.find((entry) => entry.name === "termisu_size");
    expect(sizeCall).toBeDefined();
    expect(sizeCall?.args[0]).toBe(1n);
    expect((sizeCall?.args[1] as number) !== 0).toBe(true);

    const cursorCall = calls.find((entry) => entry.name === "termisu_set_cursor");
    expect(cursorCall?.args).toEqual([1n, 12, 4]);
  });

  it("passes codepoints and optional style pointers to setCell", () => {
    const { termisu, calls } = buildMockTermisu();
    const smileCodepoint = "🙂".codePointAt(0) ?? 0;

    termisu.setCell(2, 3, "🙂", {
      fg: Color.green,
      bg: Color.default,
      attr: attrs(Attribute.Bold, Attribute.Underline),
    });
    termisu.setCell(4, 5, 65);

    const setCellCalls = calls.filter((entry) => entry.name === "termisu_set_cell");
    expect(setCellCalls).toHaveLength(2);
    expect(setCellCalls[0]?.args[3]).toBe(smileCodepoint);
    expect((setCellCalls[0]?.args[4] as number) !== 0).toBe(true);
    expect(setCellCalls[1]?.args[3]).toBe(65);
    expect(setCellCalls[1]?.args[4]).toBe(0);
  });

  it("rejects empty string characters before native call", () => {
    const { termisu } = buildMockTermisu();
    expect(() => termisu.setCell(0, 0, "")).toThrow("Character must not be empty");
  });

  it("returns null for timeout and none events in pollEvent", () => {
    const timeout = buildMockTermisu({
      termisu_poll_event: () => Status.Timeout,
    }).termisu;
    expect(timeout.pollEvent(0)).toBeNull();

    const okNone = buildMockTermisu().termisu;
    expect(okNone.pollEvent(0)).toBeNull();
  });

  it("throws TermisuError and preserves handle when destroy fails", () => {
    const { termisu } = buildMockTermisu({
      termisu_destroy: () => Status.InvalidHandle,
    });

    expect(() => termisu.destroy()).toThrow(TermisuError);
    expect(termisu.handle).toBe(1n);
  });

  it("sets handle to zero after successful destroy and enforces closed-handle checks", () => {
    const { termisu } = buildMockTermisu();

    termisu.destroy();
    expect(termisu.handle).toBe(0n);
    expect(() => termisu.clear()).toThrow(TermisuError);
  });

  it("forwards timer toggles and clearError", () => {
    const { termisu, calls } = buildMockTermisu();

    termisu.enableTimer(16);
    termisu.enableSystemTimer(16);
    termisu.disableTimer();
    termisu.clearError();

    const names = calls.map((entry) => entry.name);
    expect(names).toContain("termisu_enable_timer_ms");
    expect(names).toContain("termisu_enable_system_timer_ms");
    expect(names).toContain("termisu_disable_timer");
    expect(names).toContain("termisu_clear_error");
  });

  it("raises TermisuError when a status call fails", () => {
    const { termisu } = buildMockTermisu({
      termisu_render: () => Status.InvalidArgument,
    });

    expect(() => termisu.render()).toThrow(TermisuError);
  });

  it("rejects operations on a closed handle before calling native symbols", () => {
    const { termisu, calls } = buildMockTermisu({}, 0n);

    expect(() => termisu.close()).toThrow(TermisuError);
    expect(() => termisu.setCursor(1, 1)).toThrow(TermisuError);
    expect(() => termisu.enableTimer(16)).toThrow(TermisuError);

    expect(calls).toHaveLength(0);
  });
});
