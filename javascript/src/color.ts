import { ColorMode } from "./constants";
import type { TermisuColor } from "./types";

function clampByte(value: number): number {
  if (!Number.isInteger(value) || value < 0 || value > 255) {
    throw new RangeError(`Color component must be 0..255, got ${value}`);
  }
  return value;
}

function makeAnsi8(index: number): TermisuColor {
  if (!Number.isInteger(index) || index < -1 || index > 7) {
    throw new RangeError(`ANSI8 index must be -1..7, got ${index}`);
  }

  return {
    mode: index === -1 ? ColorMode.Default : ColorMode.Ansi8,
    index,
  };
}

function makeAnsi256(index: number): TermisuColor {
  if (!Number.isInteger(index) || index < 0 || index > 255) {
    throw new RangeError(`ANSI256 index must be 0..255, got ${index}`);
  }

  return {
    mode: ColorMode.Ansi256,
    index,
  };
}

function makeRgb(r: number, g: number, b: number): TermisuColor {
  return {
    mode: ColorMode.Rgb,
    r: clampByte(r),
    g: clampByte(g),
    b: clampByte(b),
  };
}

function fromHex(hex: string): TermisuColor {
  const raw = hex.startsWith("#") ? hex.slice(1) : hex;
  if (!/^[0-9a-fA-F]{6}$/.test(raw)) {
    throw new RangeError(`Hex color must be RRGGBB or #RRGGBB, got ${hex}`);
  }

  const r = Number.parseInt(raw.slice(0, 2), 16);
  const g = Number.parseInt(raw.slice(2, 4), 16);
  const b = Number.parseInt(raw.slice(4, 6), 16);
  return makeRgb(r, g, b);
}

function grayscale(level: number): TermisuColor {
  if (!Number.isInteger(level) || level < 0 || level > 23) {
    throw new RangeError(`Grayscale level must be 0..23, got ${level}`);
  }

  return makeAnsi256(232 + level);
}

const namedAnsi8 = {
  black: 0,
  red: 1,
  green: 2,
  yellow: 3,
  blue: 4,
  magenta: 5,
  cyan: 6,
  white: 7,
} as const;

const namedBright = {
  bright_black: 8,
  bright_red: 9,
  bright_green: 10,
  bright_yellow: 11,
  bright_blue: 12,
  bright_magenta: 13,
  bright_cyan: 14,
  bright_white: 15,
} as const;

interface ColorApi {
  ansi8(index: number): TermisuColor;
  ansi256(index: number): TermisuColor;
  rgb(r: number, g: number, b: number): TermisuColor;
  from_hex(hex: string): TermisuColor;
  fromHex(hex: string): TermisuColor;
  grayscale(level: number): TermisuColor;
  default: TermisuColor;
  black: TermisuColor;
  red: TermisuColor;
  green: TermisuColor;
  yellow: TermisuColor;
  blue: TermisuColor;
  magenta: TermisuColor;
  cyan: TermisuColor;
  white: TermisuColor;
  bright_black: TermisuColor;
  bright_red: TermisuColor;
  bright_green: TermisuColor;
  bright_yellow: TermisuColor;
  bright_blue: TermisuColor;
  bright_magenta: TermisuColor;
  bright_cyan: TermisuColor;
  bright_white: TermisuColor;
}

const colorObject: Partial<ColorApi> = {
  ansi8: makeAnsi8,
  ansi256: makeAnsi256,
  rgb: makeRgb,
  from_hex: fromHex,
  fromHex,
  grayscale,
};

Object.defineProperty(colorObject, "default", {
  enumerable: true,
  get() {
    return makeAnsi8(-1);
  },
});

for (const [name, index] of Object.entries(namedAnsi8)) {
  Object.defineProperty(colorObject, name, {
    enumerable: true,
    get() {
      return makeAnsi8(index);
    },
  });
}

for (const [name, index] of Object.entries(namedBright)) {
  Object.defineProperty(colorObject, name, {
    enumerable: true,
    get() {
      return makeAnsi256(index);
    },
  });
}

export const Color = Object.freeze(colorObject) as ColorApi;
