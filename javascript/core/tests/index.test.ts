import { describe, expect, it } from "bun:test";

import * as api from "../src/index";

describe("index exports", () => {
  it("re-exports primary runtime API", () => {
    expect(api.Termisu).toBeDefined();
    expect(api.Color).toBeDefined();
    expect(api.Attribute).toBeDefined();
    expect(api.Status.Ok).toBe(0);
  });
});
