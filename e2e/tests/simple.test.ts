import { expect, test } from "@microsoft/tui-test";

/**
 * E2E tests for the Termisu simple example.
 *
 * Tests verify:
 * - Basic cell rendering with colors
 * - Text attributes (bold, underline, strikethrough)
 * - Cursor positioning
 * - Input handling
 */

test.use({
  program: {
    file: "../bin/simple",
    args: [],
  },
});

test.describe("Simple Example", () => {
  test("displays 'Hi' greeting", async ({ terminal }) => {
    await expect(terminal.getByText("Hi")).toBeVisible();
  });

  test("displays strikethrough text", async ({ terminal }) => {
    await expect(terminal.getByText("Strikethrough")).toBeVisible();
  });

  test("responds to key press", async ({ terminal }) => {
    await expect(terminal.getByText("Hi")).toBeVisible();

    terminal.write("a");

    await expect(terminal.getByText(/You pressed:.*'a'/g)).toBeVisible();
  });

  test("matches visual snapshot", async ({ terminal }) => {
    await expect(terminal.getByText("Hi")).toBeVisible();
    await expect(terminal).toMatchSnapshot();
  });
});
