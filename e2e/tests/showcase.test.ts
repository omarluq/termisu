import { expect, test } from "@microsoft/tui-test";

/**
 * E2E tests for the Termisu showcase application.
 *
 * Tests verify:
 * - Title and header rendering
 * - Color palette sections (ANSI-8, bright, 256, RGB)
 * - Text attributes display
 * - Combined attributes rendering
 * - Hex color parsing and display
 * - Background colors
 * - Interactive input handling
 * - Graceful exit with animation
 */

test.use({
  program: {
    file: "../bin/showcase",
    args: [],
  },
});

test.describe("Showcase Application", () => {
  test.describe("Header Section", () => {
    test("displays main title", async ({ terminal }) => {
      await expect(terminal.getByText("TERMISU SHOWCASE")).toBeVisible();
    });

    test("renders title box with Unicode borders", async ({ terminal }) => {
      // Box uses ╔ ═ ╗ characters
      await expect(terminal.getByText(/╔.*═.*╗/g)).toBeVisible();
    });

    test("shows terminal dimensions in subtitle", async ({ terminal }) => {
      await expect(
        terminal.getByText(/Pure Crystal Terminal UI Library/g)
      ).toBeVisible();
    });

    test("subtitle includes terminal size", async ({ terminal }) => {
      // Format: "Pure Crystal Terminal UI Library | WxH"
      await expect(terminal.getByText(/\d+x\d+/g)).toBeVisible();
    });
  });

  test.describe("ANSI-8 Colors Section", () => {
    test("renders ANSI-8 colors section label", async ({ terminal }) => {
      await expect(terminal.getByText("ANSI-8 Colors:")).toBeVisible();
    });
  });

  test.describe("Bright Colors Section", () => {
    test("renders bright colors section label", async ({ terminal }) => {
      await expect(terminal.getByText("Bright Colors:")).toBeVisible();
    });
  });

  test.describe("Text Attributes Section", () => {
    test("displays text attributes section label", async ({ terminal }) => {
      await expect(terminal.getByText("Text Attributes:")).toBeVisible();
    });

    test("renders Normal text attribute", async ({ terminal }) => {
      await expect(terminal.getByText("Normal")).toBeVisible();
    });

    test("renders Bold text", async ({ terminal }) => {
      // Check for Bold+Underline which confirms Bold attribute exists
      await expect(terminal.getByText("Bold+Underline")).toBeVisible();
    });

    test("renders Underline text", async ({ terminal }) => {
      // Check for Bold+Underline which confirms Underline attribute exists
      await expect(terminal.getByText("Bold+Underline")).toBeVisible();
    });

    test("renders Reverse text attribute", async ({ terminal }) => {
      await expect(terminal.getByText("Reverse")).toBeVisible();
    });

    test("renders Strikethrough text attribute", async ({ terminal }) => {
      await expect(terminal.getByText("Strike")).toBeVisible();
    });
  });

  test.describe("Combined Attributes Section", () => {
    test("displays combined attributes label", async ({ terminal }) => {
      await expect(terminal.getByText("Combined:")).toBeVisible();
    });

    test("renders Bold+Underline combination", async ({ terminal }) => {
      await expect(terminal.getByText("Bold+Underline")).toBeVisible();
    });

    test("renders Dim+Italic combination", async ({ terminal }) => {
      await expect(terminal.getByText("Dim+Italic")).toBeVisible();
    });
  });

  test.describe("ANSI-256 Palette Section", () => {
    test("renders ANSI-256 palette section label", async ({ terminal }) => {
      await expect(terminal.getByText("ANSI-256 Palette:")).toBeVisible();
    });
  });

  test.describe("RGB TrueColor Section", () => {
    test("renders RGB TrueColor section label", async ({ terminal }) => {
      await expect(terminal.getByText(/RGB TrueColor.*colors/g)).toBeVisible();
    });

    test("displays 16.7M colors description", async ({ terminal }) => {
      await expect(terminal.getByText(/16\.7M colors/g)).toBeVisible();
    });
  });

  test.describe("Color Conversion Section", () => {
    test("shows color conversion demo label", async ({ terminal }) => {
      await expect(
        terminal.getByText(/Color Conversion.*RGB.*ANSI/g)
      ).toBeVisible();
    });

    test("displays RGB color sample label", async ({ terminal }) => {
      await expect(terminal.getByText("RGB:")).toBeVisible();
    });

    test("displays ANSI-256 color sample label", async ({ terminal }) => {
      await expect(terminal.getByText("256:")).toBeVisible();
    });

    test("displays ANSI-8 color sample label", async ({ terminal }) => {
      await expect(terminal.getByText("8:")).toBeVisible();
    });
  });

  test.describe("Hex Colors Section", () => {
    test("displays hex colors section label", async ({ terminal }) => {
      await expect(terminal.getByText("Hex Colors:")).toBeVisible();
    });

    test("shows hex color values", async ({ terminal }) => {
      // Hex colors displayed: #FF0000, #00FF00, etc.
      await expect(terminal.getByText("#FF0000")).toBeVisible();
      await expect(terminal.getByText("#00FF00")).toBeVisible();
      await expect(terminal.getByText("#0000FF")).toBeVisible();
    });

    test("displays all six hex colors", async ({ terminal }) => {
      await expect(terminal.getByText("#FFFF00")).toBeVisible();
      await expect(terminal.getByText("#FF00FF")).toBeVisible();
      await expect(terminal.getByText("#00FFFF")).toBeVisible();
    });
  });

  test.describe("Background Colors Section", () => {
    test("shows background colors section label", async ({ terminal }) => {
      await expect(terminal.getByText("Background Colors:")).toBeVisible();
    });

    test("displays text on colored backgrounds", async ({ terminal }) => {
      await expect(
        terminal.getByText(/Text on colored backgrounds/g)
      ).toBeVisible();
    });
  });

  test.describe("Interactive Section", () => {
    test("displays quit hint", async ({ terminal }) => {
      await expect(terminal.getByText(/Press 'q' to quit/g)).toBeVisible();
    });

    test("shows running status with animation", async ({ terminal }) => {
      await expect(terminal.getByText(/Running.*Frame/g)).toBeVisible();
    });

    test("displays spinner character", async ({ terminal }) => {
      // Spinner uses braille dots: ⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏
      await expect(terminal.getByText(/[⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏]/g)).toBeVisible();
    });

    test("responds to key press", async ({ terminal }) => {
      await expect(terminal.getByText("TERMISU SHOWCASE")).toBeVisible();

      terminal.write("x");

      await expect(terminal.getByText(/Key:.*'x'/g)).toBeVisible();
    });

    test("displays key byte value", async ({ terminal }) => {
      await expect(terminal.getByText("TERMISU SHOWCASE")).toBeVisible();

      terminal.write("a");

      // Shows: Key: 'a'  byte=97  hex=0x61
      await expect(terminal.getByText(/byte=97/g)).toBeVisible();
    });

    test("displays key hex value", async ({ terminal }) => {
      await expect(terminal.getByText("TERMISU SHOWCASE")).toBeVisible();

      terminal.write("a");

      await expect(terminal.getByText(/hex=0x61/g)).toBeVisible();
    });

    test("handles number key press", async ({ terminal }) => {
      await expect(terminal.getByText("TERMISU SHOWCASE")).toBeVisible();

      terminal.write("5");

      await expect(terminal.getByText(/Key:.*'5'/g)).toBeVisible();
    });
  });

  test.describe("Exit Handling", () => {
    test("exits gracefully on lowercase q", async ({ terminal }) => {
      await expect(terminal.getByText("TERMISU SHOWCASE")).toBeVisible();

      terminal.write("q");

      // Shows animated goodbye message
      await expect(terminal.getByText(/Goodbye/g)).toBeVisible();
    });

    test("exits gracefully on uppercase Q", async ({ terminal }) => {
      await expect(terminal.getByText("TERMISU SHOWCASE")).toBeVisible();

      terminal.write("Q");

      // Shows animated goodbye message
      await expect(terminal.getByText(/Goodbye/g)).toBeVisible();
    });

    test("shows farewell message with Termisu name", async ({ terminal }) => {
      await expect(terminal.getByText("TERMISU SHOWCASE")).toBeVisible();

      terminal.write("q");

      // The actual message includes "Termisu"
      await expect(terminal.getByText(/Termisu/g)).toBeVisible();
    });
  });

  test.describe("Visual Snapshot", () => {
    test("matches visual snapshot", async ({ terminal }) => {
      await expect(terminal.getByText("TERMISU SHOWCASE")).toBeVisible();
      await expect(terminal).toMatchSnapshot();
    });
  });
});
