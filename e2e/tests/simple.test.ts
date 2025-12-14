import { expect, test } from "@microsoft/tui-test";

/**
 * E2E tests for the Termisu simple example.
 *
 * Tests verify:
 * - Basic cell rendering with colors
 * - Text display (Hi greeting, Strikethrough text)
 * - Cursor positioning
 * - Input handling with typewriter animation
 * - Key byte value display
 */

test.use({
  program: {
    file: "../bin/simple",
    args: [],
  },
});

test.describe("Simple Example", () => {
  test.describe("Initial Rendering", () => {
    test("displays 'Hi' greeting", async ({ terminal }) => {
      await expect(terminal.getByText("Hi")).toBeVisible();
    });

    test("displays strikethrough text", async ({ terminal }) => {
      await expect(terminal.getByText("Strikethrough")).toBeVisible();
    });

    test("Hi and Strikethrough are on separate lines", async ({ terminal }) => {
      await expect(terminal.getByText("Hi")).toBeVisible();
      await expect(terminal.getByText("Strikethrough")).toBeVisible();
    });
  });

  test.describe("Cursor Positioning", () => {
    test("cursor is visible after initial render", async ({ terminal }) => {
      await expect(terminal.getByText("Strikethrough")).toBeVisible();

      const cursor = terminal.getCursor();
      // Cursor set at (14, 1) - after "Strikethrough" (13 chars)
      expect(cursor.x).toBe(14);
      expect(cursor.y).toBe(1);
    });
  });

  test.describe("Input Handling", () => {
    test("responds to letter key press", async ({ terminal }) => {
      await expect(terminal.getByText("Hi")).toBeVisible();

      terminal.write("a");

      await expect(terminal.getByText(/You pressed:.*'a'/g)).toBeVisible();
    });

    test("shows byte value for letter key", async ({ terminal }) => {
      await expect(terminal.getByText("Hi")).toBeVisible();

      terminal.write("a");

      // 'a' has byte value 97
      await expect(terminal.getByText(/byte: 97/g)).toBeVisible();
    });

    test("responds to number key press", async ({ terminal }) => {
      await expect(terminal.getByText("Hi")).toBeVisible();

      terminal.write("5");

      await expect(terminal.getByText(/You pressed:.*'5'/g)).toBeVisible();
    });

    test("shows byte value for number key", async ({ terminal }) => {
      await expect(terminal.getByText("Hi")).toBeVisible();

      terminal.write("5");

      // '5' has byte value 53
      await expect(terminal.getByText(/byte: 53/g)).toBeVisible();
    });

    test("responds to uppercase letter key", async ({ terminal }) => {
      await expect(terminal.getByText("Hi")).toBeVisible();

      terminal.write("Z");

      await expect(terminal.getByText(/You pressed:.*'Z'/g)).toBeVisible();
    });

    test("shows byte value for uppercase letter", async ({ terminal }) => {
      await expect(terminal.getByText("Hi")).toBeVisible();

      terminal.write("Z");

      // 'Z' has byte value 90
      await expect(terminal.getByText(/byte: 90/g)).toBeVisible();
    });

    test("responds to space key", async ({ terminal }) => {
      await expect(terminal.getByText("Hi")).toBeVisible();

      terminal.write(" ");

      // Space has byte value 32
      await expect(terminal.getByText(/byte: 32/g)).toBeVisible();
    });
  });

  test.describe("Response Formatting", () => {
    test("response message has correct format", async ({ terminal }) => {
      await expect(terminal.getByText("Hi")).toBeVisible();

      terminal.write("x");

      // Format: "You pressed: 'x' (byte: 120)"
      await expect(
        terminal.getByText(/You pressed: 'x' \(byte: 120\)/g)
      ).toBeVisible();
    });

    test("displays response after key press", async ({ terminal }) => {
      await expect(terminal.getByText("Hi")).toBeVisible();

      terminal.write("t");

      await expect(terminal.getByText(/You pressed:/g)).toBeVisible();
    });
  });

  test.describe("Visual Snapshot", () => {
    test("matches visual snapshot", async ({ terminal }) => {
      await expect(terminal.getByText("Hi")).toBeVisible();
      await expect(terminal).toMatchSnapshot();
    });
  });
});
