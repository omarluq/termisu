import { describe, expect, it } from "bun:test";

import { Status } from "../src/constants";
import { TermisuError } from "../src/errors";

describe("TermisuError", () => {
  it("stores status and prefixes message with action when present", () => {
    const err = new TermisuError(Status.InvalidHandle, "bad handle", "termisu_destroy");
    expect(err).toBeInstanceOf(Error);
    expect(err.name).toBe("TermisuError");
    expect(err.status).toBe(Status.InvalidHandle);
    expect(err.message).toBe("termisu_destroy: bad handle");
  });

  it("uses raw message when action is omitted", () => {
    const err = new TermisuError(Status.Error, "native failure");
    expect(err.message).toBe("native failure");
    expect(err.status).toBe(Status.Error);
  });
});
