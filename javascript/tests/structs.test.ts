import { describe, expect, it } from "bun:test";

import { ColorMode, EventType, STRUCT } from "../src/constants";
import {
  createEventBuffer,
  createSizeBuffer,
  createStyleBuffer,
  readEvent,
  readSize,
} from "../src/structs";

const LE = true;

describe("struct helpers", () => {
  it("creates and reads size buffers", () => {
    const buffer = createSizeBuffer();
    const view = new DataView(buffer);
    view.setInt32(STRUCT.size.width, 120, LE);
    view.setInt32(STRUCT.size.height, 40, LE);

    expect(readSize(buffer)).toEqual({ width: 120, height: 40 });
  });

  it("writes default style values when style is omitted", () => {
    const buffer = createStyleBuffer();
    const view = new DataView(buffer);

    expect(view.getUint8(STRUCT.cellStyle.fg + STRUCT.color.mode)).toBe(ColorMode.Default);
    expect(view.getInt32(STRUCT.cellStyle.fg + STRUCT.color.index, LE)).toBe(-1);
    expect(view.getUint16(STRUCT.cellStyle.attr, LE)).toBe(0);
  });

  it("writes style colors and attributes", () => {
    const buffer = createStyleBuffer({
      fg: { mode: ColorMode.Rgb, r: 1, g: 2, b: 3 },
      bg: { mode: ColorMode.Ansi256, index: 201 },
      attr: 0xff,
    });
    const view = new DataView(buffer);

    expect(view.getUint8(STRUCT.cellStyle.fg + STRUCT.color.mode)).toBe(ColorMode.Rgb);
    expect(view.getUint8(STRUCT.cellStyle.fg + STRUCT.color.r)).toBe(1);
    expect(view.getUint8(STRUCT.cellStyle.fg + STRUCT.color.g)).toBe(2);
    expect(view.getUint8(STRUCT.cellStyle.fg + STRUCT.color.b)).toBe(3);
    expect(view.getUint8(STRUCT.cellStyle.bg + STRUCT.color.mode)).toBe(ColorMode.Ansi256);
    expect(view.getInt32(STRUCT.cellStyle.bg + STRUCT.color.index, LE)).toBe(201);
    expect(view.getUint16(STRUCT.cellStyle.attr, LE)).toBe(0xff);
  });

  it("defaults non-default color index to zero when omitted", () => {
    const buffer = createStyleBuffer({
      fg: { mode: ColorMode.Ansi8 } as unknown as { mode: ColorMode.Ansi8; index: number },
    });
    const view = new DataView(buffer);

    expect(view.getUint8(STRUCT.cellStyle.fg + STRUCT.color.mode)).toBe(ColorMode.Ansi8);
    expect(view.getInt32(STRUCT.cellStyle.fg + STRUCT.color.index, LE)).toBe(0);
  });

  it("parses all event variants from ABI buffers", () => {
    const key = createEventBuffer();
    const keyView = new DataView(key);
    keyView.setUint8(STRUCT.event.eventType, EventType.Key);
    keyView.setUint8(STRUCT.event.modifiers, 4);
    keyView.setInt32(STRUCT.event.keyCode, 65, LE);
    keyView.setInt32(STRUCT.event.keyChar, 65, LE);
    expect(readEvent(key)).toEqual({ type: EventType.Key, modifiers: 4, keyCode: 65, keyChar: 65 });

    const mouse = createEventBuffer();
    const mouseView = new DataView(mouse);
    mouseView.setUint8(STRUCT.event.eventType, EventType.Mouse);
    mouseView.setUint8(STRUCT.event.modifiers, 1);
    mouseView.setInt32(STRUCT.event.mouseX, 10, LE);
    mouseView.setInt32(STRUCT.event.mouseY, 20, LE);
    mouseView.setInt32(STRUCT.event.mouseButton, 2, LE);
    mouseView.setUint8(STRUCT.event.mouseMotion, 1);
    expect(readEvent(mouse)).toEqual({
      type: EventType.Mouse,
      modifiers: 1,
      x: 10,
      y: 20,
      button: 2,
      motion: true,
    });

    const resize = createEventBuffer();
    const resizeView = new DataView(resize);
    resizeView.setUint8(STRUCT.event.eventType, EventType.Resize);
    resizeView.setInt32(STRUCT.event.resizeWidth, 90, LE);
    resizeView.setInt32(STRUCT.event.resizeHeight, 30, LE);
    resizeView.setUint8(STRUCT.event.resizeHasOld, 1);
    resizeView.setInt32(STRUCT.event.resizeOldWidth, 80, LE);
    resizeView.setInt32(STRUCT.event.resizeOldHeight, 24, LE);
    expect(readEvent(resize)).toEqual({
      type: EventType.Resize,
      modifiers: 0,
      width: 90,
      height: 30,
      oldWidth: 80,
      oldHeight: 24,
    });

    const tick = createEventBuffer();
    const tickView = new DataView(tick);
    tickView.setUint8(STRUCT.event.eventType, EventType.Tick);
    tickView.setBigUint64(STRUCT.event.tickFrame, 11n, LE);
    tickView.setBigInt64(STRUCT.event.tickElapsedNs, 200n, LE);
    tickView.setBigInt64(STRUCT.event.tickDeltaNs, 16n, LE);
    tickView.setBigUint64(STRUCT.event.tickMissedTicks, 2n, LE);
    expect(readEvent(tick)).toEqual({
      type: EventType.Tick,
      modifiers: 0,
      frame: 11n,
      elapsedNs: 200n,
      deltaNs: 16n,
      missedTicks: 2n,
    });

    const mode = createEventBuffer();
    const modeView = new DataView(mode);
    modeView.setUint8(STRUCT.event.eventType, EventType.ModeChange);
    modeView.setUint32(STRUCT.event.modeCurrent, 3, LE);
    modeView.setUint8(STRUCT.event.modeHasPrevious, 1);
    modeView.setUint32(STRUCT.event.modePrevious, 1, LE);
    expect(readEvent(mode)).toEqual({
      type: EventType.ModeChange,
      modifiers: 0,
      current: 3,
      previous: 1,
    });
  });

  it("returns a none event when the event type is unknown", () => {
    const buffer = createEventBuffer();
    const view = new DataView(buffer);
    view.setUint8(STRUCT.event.eventType, EventType.None);
    view.setUint8(STRUCT.event.modifiers, 9);
    expect(readEvent(buffer)).toEqual({ type: EventType.None, modifiers: 9 });
  });

  it("maps null-ish event payloads correctly", () => {
    const key = createEventBuffer();
    const keyView = new DataView(key);
    keyView.setUint8(STRUCT.event.eventType, EventType.Key);
    keyView.setInt32(STRUCT.event.keyCode, 13, LE);
    keyView.setInt32(STRUCT.event.keyChar, -1, LE);
    expect(readEvent(key)).toEqual({
      type: EventType.Key,
      modifiers: 0,
      keyCode: 13,
      keyChar: null,
    });

    const resize = createEventBuffer();
    const resizeView = new DataView(resize);
    resizeView.setUint8(STRUCT.event.eventType, EventType.Resize);
    resizeView.setInt32(STRUCT.event.resizeWidth, 100, LE);
    resizeView.setInt32(STRUCT.event.resizeHeight, 50, LE);
    resizeView.setUint8(STRUCT.event.resizeHasOld, 0);
    expect(readEvent(resize)).toEqual({
      type: EventType.Resize,
      modifiers: 0,
      width: 100,
      height: 50,
      oldWidth: null,
      oldHeight: null,
    });

    const mode = createEventBuffer();
    const modeView = new DataView(mode);
    modeView.setUint8(STRUCT.event.eventType, EventType.ModeChange);
    modeView.setUint32(STRUCT.event.modeCurrent, 2, LE);
    modeView.setUint8(STRUCT.event.modeHasPrevious, 0);
    expect(readEvent(mode)).toEqual({
      type: EventType.ModeChange,
      modifiers: 0,
      current: 2,
      previous: null,
    });
  });
});
