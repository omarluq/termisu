import { ColorMode, EventType, STRUCT } from "./constants";
import type { AnyEvent, CellStyle, Size } from "./types";

const LITTLE_ENDIAN = true;

export function createSizeBuffer(): ArrayBuffer {
  return new ArrayBuffer(STRUCT.size.size);
}

export function readSize(buffer: ArrayBuffer): Size {
  const view = new DataView(buffer);
  return {
    width: view.getInt32(STRUCT.size.width, LITTLE_ENDIAN),
    height: view.getInt32(STRUCT.size.height, LITTLE_ENDIAN),
  };
}

function writeColor(view: DataView, offset: number, color?: CellStyle["fg"]): void {
  const mode = color?.mode ?? ColorMode.Default;
  view.setUint8(offset + STRUCT.color.mode, mode);

  let index = -1;
  if (color && (color.mode === ColorMode.Ansi8 || color.mode === ColorMode.Ansi256)) {
    index = color.index ?? 0;
  }
  view.setInt32(offset + STRUCT.color.index, index, LITTLE_ENDIAN);

  view.setUint8(offset + STRUCT.color.r, color?.r ?? 0);
  view.setUint8(offset + STRUCT.color.g, color?.g ?? 0);
  view.setUint8(offset + STRUCT.color.b, color?.b ?? 0);
}

export function createStyleBuffer(style?: CellStyle): ArrayBuffer {
  const buffer = new ArrayBuffer(STRUCT.cellStyle.size);
  const view = new DataView(buffer);

  writeColor(view, STRUCT.cellStyle.fg, style?.fg);
  writeColor(view, STRUCT.cellStyle.bg, style?.bg);
  view.setUint16(STRUCT.cellStyle.attr, style?.attr ?? 0, LITTLE_ENDIAN);

  return buffer;
}

export function createEventBuffer(): ArrayBuffer {
  return new ArrayBuffer(STRUCT.event.size);
}

export function readEvent(buffer: ArrayBuffer): AnyEvent {
  const view = new DataView(buffer);
  const type = view.getUint8(STRUCT.event.eventType) as EventType;
  const modifiers = view.getUint8(STRUCT.event.modifiers);

  switch (type) {
    case EventType.Key: {
      const rawChar = view.getInt32(STRUCT.event.keyChar, LITTLE_ENDIAN);
      return {
        type,
        modifiers,
        keyCode: view.getInt32(STRUCT.event.keyCode, LITTLE_ENDIAN),
        keyChar: rawChar >= 0 ? rawChar : null,
      };
    }

    case EventType.Mouse:
      return {
        type,
        modifiers,
        x: view.getInt32(STRUCT.event.mouseX, LITTLE_ENDIAN),
        y: view.getInt32(STRUCT.event.mouseY, LITTLE_ENDIAN),
        button: view.getInt32(STRUCT.event.mouseButton, LITTLE_ENDIAN),
        motion: view.getUint8(STRUCT.event.mouseMotion) !== 0,
      };

    case EventType.Resize: {
      const hasOld = view.getUint8(STRUCT.event.resizeHasOld) !== 0;
      return {
        type,
        modifiers,
        width: view.getInt32(STRUCT.event.resizeWidth, LITTLE_ENDIAN),
        height: view.getInt32(STRUCT.event.resizeHeight, LITTLE_ENDIAN),
        oldWidth: hasOld ? view.getInt32(STRUCT.event.resizeOldWidth, LITTLE_ENDIAN) : null,
        oldHeight: hasOld ? view.getInt32(STRUCT.event.resizeOldHeight, LITTLE_ENDIAN) : null,
      };
    }

    case EventType.Tick:
      return {
        type,
        modifiers,
        frame: view.getBigUint64(STRUCT.event.tickFrame, LITTLE_ENDIAN),
        elapsedNs: view.getBigInt64(STRUCT.event.tickElapsedNs, LITTLE_ENDIAN),
        deltaNs: view.getBigInt64(STRUCT.event.tickDeltaNs, LITTLE_ENDIAN),
        missedTicks: view.getBigUint64(STRUCT.event.tickMissedTicks, LITTLE_ENDIAN),
      };

    case EventType.ModeChange: {
      const hasPrevious = view.getUint8(STRUCT.event.modeHasPrevious) !== 0;
      return {
        type,
        modifiers,
        current: view.getUint32(STRUCT.event.modeCurrent, LITTLE_ENDIAN),
        previous: hasPrevious ? view.getUint32(STRUCT.event.modePrevious, LITTLE_ENDIAN) : null,
      };
    }

    default:
      return {
        type: EventType.None,
        modifiers,
      };
  }
}
