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

// Matches include/termisu/ffi.h (validated on x86_64 Linux)
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
