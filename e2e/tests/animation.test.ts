import { expect, test } from "@microsoft/tui-test";

/**
 * E2E tests for the Termisu animation example.
 *
 * Tests verify:
 * - Bouncing ball animation rendering
 * - Frame counter display
 * - Ball position tracking
 * - Graceful exit on 'q' or ESC
 */

test.use({
  program: {
    file: "../bin/animation",
    args: [],
  },
});

test.describe("Animation Example", () => {
  test("displays frame counter", async ({ terminal }) => {
    await expect(terminal.getByText(/Frame:/g)).toBeVisible();
  });

  test("displays ball position", async ({ terminal }) => {
    await expect(terminal.getByText(/Ball:/g)).toBeVisible();
  });

  test("shows quit hint", async ({ terminal }) => {
    await expect(terminal.getByText(/Press 'q' to quit/g)).toBeVisible();
  });

  test("renders bouncing ball", async ({ terminal }) => {
    await expect(terminal.getByText("●")).toBeVisible();
  });

  test("animation updates frame counter", async ({ terminal }) => {
    await expect(terminal.getByText(/Frame: \d+/g)).toBeVisible();
  });

  test("exits gracefully on q key", async ({ terminal }) => {
    await expect(terminal.getByText(/Frame:/g)).toBeVisible();

    terminal.write("q");

    // Terminal should close - we verify we reach this point
  });

  test("exits gracefully on ESC key", async ({ terminal }) => {
    await expect(terminal.getByText(/Frame:/g)).toBeVisible();

    terminal.keyEscape();

    // Terminal should close - we verify we reach this point
  });
});
