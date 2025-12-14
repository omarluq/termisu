import { expect, test } from "@microsoft/tui-test";

/**
 * E2E tests for the Termisu showcase application.
 *
 * Tests verify:
 * - Title and header rendering
 * - Color palette sections (ANSI-8, bright, 256, RGB)
 * - Text attributes display
 * - Interactive input handling
 * - Graceful exit on 'q'
 */

test.use({
  program: {
    file: "../bin/showcase",
    args: [],
  },
});

test.describe("Showcase Application", () => {
  test("displays main title", async ({ terminal }) => {
    await expect(terminal.getByText("TERMISU SHOWCASE")).toBeVisible();
  });

  test("shows terminal dimensions in subtitle", async ({ terminal }) => {
    await expect(
      terminal.getByText(/Pure Crystal Terminal UI Library/g)
    ).toBeVisible();
  });

  test("renders ANSI-8 colors section", async ({ terminal }) => {
    await expect(terminal.getByText("ANSI-8 Colors:")).toBeVisible();
  });

  test("renders bright colors section", async ({ terminal }) => {
    await expect(terminal.getByText("Bright Colors:")).toBeVisible();
  });

  test("displays text attributes section", async ({ terminal }) => {
    await expect(terminal.getByText("Text Attributes:")).toBeVisible();
    // Attributes are rendered with their respective styles (Bold, Underline, etc.)
    // The label "Normal" is rendered without styling
    await expect(terminal.getByText("Normal")).toBeVisible();
  });

  test("renders ANSI-256 palette section", async ({ terminal }) => {
    await expect(terminal.getByText("ANSI-256 Palette:")).toBeVisible();
  });

  test("renders RGB TrueColor section", async ({ terminal }) => {
    await expect(terminal.getByText(/RGB TrueColor.*colors/g)).toBeVisible();
  });

  test("shows color conversion demo", async ({ terminal }) => {
    await expect(
      terminal.getByText(/Color Conversion.*RGB.*ANSI/g)
    ).toBeVisible();
  });

  test("displays hex colors section", async ({ terminal }) => {
    await expect(terminal.getByText("Hex Colors:")).toBeVisible();
  });

  test("shows background colors section", async ({ terminal }) => {
    await expect(terminal.getByText("Background Colors:")).toBeVisible();
  });

  test("displays quit hint", async ({ terminal }) => {
    await expect(terminal.getByText(/Press 'q' to quit/g)).toBeVisible();
  });

  test("shows running status with animation", async ({ terminal }) => {
    await expect(terminal.getByText(/Running.*Frame/g)).toBeVisible();
  });

  test("responds to key press", async ({ terminal }) => {
    await expect(terminal.getByText("TERMISU SHOWCASE")).toBeVisible();

    terminal.write("x");

    await expect(terminal.getByText(/Key:.*'x'/g)).toBeVisible();
  });

  test("exits gracefully on q key", async ({ terminal }) => {
    await expect(terminal.getByText("TERMISU SHOWCASE")).toBeVisible();

    terminal.write("q");

    // The actual message is "Thanks for trying Termisu! Goodbye! 👋"
    await expect(terminal.getByText(/Goodbye/g)).toBeVisible();
  });

  test("matches visual snapshot", async ({ terminal }) => {
    await expect(terminal.getByText("TERMISU SHOWCASE")).toBeVisible();
    await expect(terminal).toMatchSnapshot();
  });
});
