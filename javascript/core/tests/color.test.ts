import { describe, expect, it } from "bun:test";

import { Color } from "../src/color";
import { ColorMode } from "../src/constants";

describe("Color API", () => {
  it("creates ANSI8, ANSI256 and RGB values", () => {
    expect(Color.ansi8(3)).toEqual({ mode: ColorMode.Ansi8, index: 3 });
    expect(Color.ansi256(129)).toEqual({ mode: ColorMode.Ansi256, index: 129 });
    expect(Color.rgb(1, 2, 3)).toEqual({ mode: ColorMode.Rgb, r: 1, g: 2, b: 3 });
  });

  it("supports default color via ansi8(-1)", () => {
    expect(Color.ansi8(-1)).toEqual({ mode: ColorMode.Default });
    expect(Color.default).toEqual({ mode: ColorMode.Default });
  });

  it("parses hex colors and keeps from_hex/fromHex aligned", () => {
    const a = Color.from_hex("#FF8040");
    const b = Color.fromHex("FF8040");
    expect(a).toEqual({ mode: ColorMode.Rgb, r: 255, g: 128, b: 64 });
    expect(b).toEqual(a);
  });

  it("maps grayscale to ANSI256 grayscale ramp", () => {
    expect(Color.grayscale(0)).toEqual({ mode: ColorMode.Ansi256, index: 232 });
    expect(Color.grayscale(23)).toEqual({ mode: ColorMode.Ansi256, index: 255 });
  });

  it("returns stable references for named getters", () => {
    expect(Color.red).toBe(Color.red);
    expect(Color.bright_cyan).toBe(Color.bright_cyan);
    expect(Color.default).toBe(Color.default);
  });

  it("validates out-of-range input", () => {
    expect(() => Color.ansi8(-2)).toThrow(RangeError);
    expect(() => Color.ansi256(256)).toThrow(RangeError);
    expect(() => Color.rgb(-1, 0, 0)).toThrow(RangeError);
    expect(() => Color.grayscale(24)).toThrow(RangeError);
    expect(() => Color.fromHex("#xyzxyz")).toThrow(RangeError);
  });
});
