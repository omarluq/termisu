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

  if (index === -1) {
    return {
      mode: ColorMode.Default,
      index: -1,
    };
  }

  return {
    mode: ColorMode.Ansi8,
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

/**
 * Convenience constructors and named colors for Termisu cell styles.
 */
interface ColorApi {
  /**
   * ANSI 8-color palette entry. Use -1 for terminal default.
   * @param index - `-1..7`
   */
  ansi8(index: number): TermisuColor;
  /**
   * ANSI 256-color palette entry.
   * @param index - `0..255`
   */
  ansi256(index: number): TermisuColor;
  /**
   * 24-bit RGB color.
   * @param r - red channel `0..255`
   * @param g - green channel `0..255`
   * @param b - blue channel `0..255`
   */
  rgb(r: number, g: number, b: number): TermisuColor;
  /**
   * Parse `RRGGBB` or `#RRGGBB` into an RGB color.
   * Alias of {@link fromHex}.
   */
  from_hex(hex: string): TermisuColor;
  /**
   * Parse `RRGGBB` or `#RRGGBB` into an RGB color.
   * Alias of {@link from_hex}.
   */
  fromHex(hex: string): TermisuColor;
  /**
   * ANSI grayscale ramp entry.
   * @param level - `0..23` (maps to ANSI256 `232..255`)
   */
  grayscale(level: number): TermisuColor;
  /** Terminal default foreground/background color. */
  default: TermisuColor;
  /** ANSI black (`0`). */
  black: TermisuColor;
  /** ANSI red (`1`). */
  red: TermisuColor;
  /** ANSI green (`2`). */
  green: TermisuColor;
  /** ANSI yellow (`3`). */
  yellow: TermisuColor;
  /** ANSI blue (`4`). */
  blue: TermisuColor;
  /** ANSI magenta (`5`). */
  magenta: TermisuColor;
  /** ANSI cyan (`6`). */
  cyan: TermisuColor;
  /** ANSI white (`7`). */
  white: TermisuColor;
  /** ANSI bright black (`8`). */
  bright_black: TermisuColor;
  /** ANSI bright red (`9`). */
  bright_red: TermisuColor;
  /** ANSI bright green (`10`). */
  bright_green: TermisuColor;
  /** ANSI bright yellow (`11`). */
  bright_yellow: TermisuColor;
  /** ANSI bright blue (`12`). */
  bright_blue: TermisuColor;
  /** ANSI bright magenta (`13`). */
  bright_magenta: TermisuColor;
  /** ANSI bright cyan (`14`). */
  bright_cyan: TermisuColor;
  /** ANSI bright white (`15`). */
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
