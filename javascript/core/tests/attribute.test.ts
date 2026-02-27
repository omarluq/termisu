import { describe, expect, it } from "bun:test";

import { Attribute, attrs } from "../src/attribute";

describe("attribute helpers", () => {
  it("keeps cursive and italic as aliases", () => {
    expect(Attribute.Cursive).toBe(Attribute.Italic);
  });

  it("builds masks while skipping nullish values", () => {
    const mask = attrs(
      Attribute.Bold,
      undefined,
      null,
      Attribute.Underline,
      Attribute.Bold,
      Attribute.Hidden
    );
    expect(mask).toBe(Attribute.Bold | Attribute.Underline | Attribute.Hidden);
  });

  it("returns zero when no flags are provided", () => {
    expect(attrs()).toBe(0);
  });
});
