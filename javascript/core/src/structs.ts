import { ColorMode, EventType, STRUCT } from "./constants";
import type { AnyEvent, CellOp, CellStyle, Size } from "./types";

const LITTLE_ENDIAN = true;
const PREEDIT_DECODER = new TextDecoder("utf-8");

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

// Writes every meaningful field, so a reused scratch view never leaks
// values from a previous call (untouched padding bytes stay zero).
export function writeStyle(view: DataView, style?: CellStyle): void {
  writeColor(view, STRUCT.cellStyle.fg, style?.fg);
  writeColor(view, STRUCT.cellStyle.bg, style?.bg);
  view.setUint16(STRUCT.cellStyle.attr, style?.attr ?? 0, LITTLE_ENDIAN);
}

export function createStyleBuffer(style?: CellStyle): ArrayBuffer {
  const buffer = new ArrayBuffer(STRUCT.cellStyle.size);
  writeStyle(new DataView(buffer), style);
  return buffer;
}

function opCodepoint(char: string | number): number {
  if (typeof char === "number") {
    return char;
  }
  const codepoint = char.codePointAt(0);
  if (codepoint === undefined) {
    throw new Error("Character must not be empty");
  }
  return codepoint;
}

// Marshals every op into one contiguous termisu_cell_op_t array so a whole
// frame crosses the FFI boundary with a single pointer.
export function createCellOpsBuffer(ops: readonly CellOp[]): ArrayBuffer {
  const buffer = new ArrayBuffer(STRUCT.cellOp.size * ops.length);
  const view = new DataView(buffer);

  let offset = 0;
  for (const op of ops) {
    view.setInt32(offset + STRUCT.cellOp.x, op.x, LITTLE_ENDIAN);
    view.setInt32(offset + STRUCT.cellOp.y, op.y, LITTLE_ENDIAN);
    view.setInt32(offset + STRUCT.cellOp.codepoint, opCodepoint(op.char), LITTLE_ENDIAN);

    const styleOffset = offset + STRUCT.cellOp.style;
    writeColor(view, styleOffset + STRUCT.cellStyle.fg, op.style?.fg);
    writeColor(view, styleOffset + STRUCT.cellStyle.bg, op.style?.bg);
    view.setUint16(styleOffset + STRUCT.cellStyle.attr, op.style?.attr ?? 0, LITTLE_ENDIAN);

    offset += STRUCT.cellOp.size;
  }

  return buffer;
}

export function createEventBuffer(): ArrayBuffer {
  return new ArrayBuffer(STRUCT.event.size);
}

export function readEvent(buffer: ArrayBuffer): AnyEvent {
  return readEventFrom(new DataView(buffer));
}

// Returns a freshly allocated event; the view (and its backing buffer) may be
// a reused scratch that the next native call overwrites.
export function readEventFrom(view: DataView): AnyEvent {
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

    case EventType.Preedit: {
      // Clamp to the inline capacity so a corrupt/out-of-contract length byte
      // can't read past the buffer (RangeError) and crash event decoding.
      const rawLen = view.getUint8(STRUCT.event.preeditLen);
      const len = Math.min(rawLen, STRUCT.event.preeditTextCapacity);
      const bytes = new Uint8Array(view.buffer, view.byteOffset + STRUCT.event.preeditText, len);
      return {
        type,
        modifiers,
        text: PREEDIT_DECODER.decode(bytes),
      };
    }

    default:
      return {
        type: EventType.None,
        modifiers,
      };
  }
}
