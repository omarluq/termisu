import { describe, expect, it } from "bun:test";

import {
  ABI_VERSION,
  ColorMode,
  EventType,
  STRUCT,
  STRUCT_LAYOUT_SIGNATURE,
  Status,
} from "../src/constants";

describe("constants", () => {
  it("exports the expected ABI and enum values", () => {
    expect(ABI_VERSION).toBe(1);
    expect(Status.Ok).toBe(0);
    expect(EventType.ModeChange).toBe(5);
    expect(ColorMode.Rgb).toBe(3);
  });

  it("defines expected ABI struct sizes", () => {
    expect(STRUCT.color.size).toBe(12);
    expect(STRUCT.cellStyle.size).toBe(28);
    expect(STRUCT.size.size).toBe(8);
    expect(STRUCT.event.size).toBe(96);
  });

  it("computes a stable non-zero layout signature", () => {
    expect(typeof STRUCT_LAYOUT_SIGNATURE).toBe("bigint");
    expect(STRUCT_LAYOUT_SIGNATURE > 0n).toBe(true);
  });
});
