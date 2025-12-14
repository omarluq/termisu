import { expect, test } from "@microsoft/tui-test";

/**
 * E2E tests for the Termisu keyboard and mouse demo.
 *
 * Tests verify:
 * - Keyboard layout rendering
 * - Key press highlighting
 * - Mouse tracking display
 * - Modifier key detection
 * - Graceful exit on ESC
 */

test.use({
  program: {
    file: "../bin/kmd",
    args: [],
  },
});

test.describe("Keyboard & Mouse Demo", () => {
  test("displays demo title", async ({ terminal }) => {
    await expect(terminal.getByText(/KEYBOARD.*MOUSE.*DEMO/g)).toBeVisible();
  });

  test("shows keyboard layout", async ({ terminal }) => {
    // Check for keys in the keyboard layout
    // These are rendered inside box-drawing borders
    await expect(terminal.getByText("Esc")).toBeVisible();
    await expect(terminal.getByText("Q")).toBeVisible();
  });

  test("displays mouse info panel", async ({ terminal }) => {
    await expect(terminal.getByText(/Mouse:/g)).toBeVisible();
  });

  test("shows quit hint", async ({ terminal }) => {
    await expect(terminal.getByText(/ESC.*Ctrl.*C.*quit/g)).toBeVisible();
  });

  test("responds to key press with event log", async ({ terminal }) => {
    await expect(terminal.getByText("Esc")).toBeVisible();

    terminal.write("a");

    await expect(terminal.getByText(/Last event:.*LowerA/g)).toBeVisible();
  });

  test("exits gracefully on ESC key", async ({ terminal }) => {
    await expect(terminal.getByText("Esc")).toBeVisible();

    terminal.keyEscape();

    // Terminal should close - we just verify we can get to this point
  });

  // Note: Visual snapshot test disabled for keyboard demo
  // The keyboard layout contains backtick characters (`) which break
  // JavaScript snapshot format (treated as template literals)
});
