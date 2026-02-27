export enum Status {
  Ok = 0,
  Timeout = 1,
  InvalidArgument = 2,
  InvalidHandle = 3,
  Rejected = 4,
  Error = 5,
}

export enum EventType {
  None = 0,
  Key = 1,
  Mouse = 2,
  Resize = 3,
  Tick = 4,
  ModeChange = 5,
}

export enum ColorMode {
  Default = 0,
  Ansi8 = 1,
  Ansi256 = 2,
  Rgb = 3,
}

export const ABI_VERSION = 1;

// Matches include/termisu/ffi.h (validated at load-time via layout signature)
export const STRUCT = {
  color: {
    size: 12,
    mode: 0,
    index: 4,
    r: 8,
    g: 9,
    b: 10,
  },
  cellStyle: {
    size: 28,
    fg: 0,
    bg: 12,
    attr: 24,
  },
  size: {
    size: 8,
    width: 0,
    height: 4,
  },
  event: {
    size: 96,
    eventType: 0,
    modifiers: 1,
    keyCode: 4,
    keyChar: 8,
    mouseX: 12,
    mouseY: 16,
    mouseButton: 20,
    mouseMotion: 24,
    resizeWidth: 28,
    resizeHeight: 32,
    resizeOldWidth: 36,
    resizeOldHeight: 40,
    resizeHasOld: 44,
    tickFrame: 48,
    tickElapsedNs: 56,
    tickDeltaNs: 64,
    tickMissedTicks: 72,
    modeCurrent: 80,
    modePrevious: 84,
    modeHasPrevious: 88,
  },
} as const;

const FNV_OFFSET_BASIS = 0xcbf29ce484222325n;
const FNV_PRIME = 0x100000001b3n;
const U64_MASK = 0xffffffffffffffffn;

function mixSignature(hash: bigint, value: number): bigint {
  return ((hash ^ BigInt(value)) * FNV_PRIME) & U64_MASK;
}

const STRUCT_LAYOUT_VALUES = [
  STRUCT.color.size,
  STRUCT.color.mode,
  STRUCT.color.index,
  STRUCT.color.r,
  STRUCT.color.g,
  STRUCT.color.b,
  STRUCT.cellStyle.size,
  STRUCT.cellStyle.fg,
  STRUCT.cellStyle.bg,
  STRUCT.cellStyle.attr,
  STRUCT.size.size,
  STRUCT.size.width,
  STRUCT.size.height,
  STRUCT.event.size,
  STRUCT.event.eventType,
  STRUCT.event.modifiers,
  STRUCT.event.keyCode,
  STRUCT.event.keyChar,
  STRUCT.event.mouseX,
  STRUCT.event.mouseY,
  STRUCT.event.mouseButton,
  STRUCT.event.mouseMotion,
  STRUCT.event.resizeWidth,
  STRUCT.event.resizeHeight,
  STRUCT.event.resizeOldWidth,
  STRUCT.event.resizeOldHeight,
  STRUCT.event.resizeHasOld,
  STRUCT.event.tickFrame,
  STRUCT.event.tickElapsedNs,
  STRUCT.event.tickDeltaNs,
  STRUCT.event.tickMissedTicks,
  STRUCT.event.modeCurrent,
  STRUCT.event.modePrevious,
  STRUCT.event.modeHasPrevious,
] as const;

export const STRUCT_LAYOUT_SIGNATURE = STRUCT_LAYOUT_VALUES.reduce(
  (hash, value) => mixSignature(hash, value),
  FNV_OFFSET_BASIS
);
