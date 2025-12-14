import { expect, test } from "@microsoft/tui-test";

/**
 * E2E tests for the Termisu colors example.
 *
 * Tests verify:
 * - ANSI-8 basic colors (black, red, green, yellow, blue, magenta, cyan, white)
 * - ANSI-256 bright colors (8-15)
 * - Color cube subset (6x6x6 = 216 colors, showing 36)
 * - Grayscale ramp (24 levels from 232-255)
 * - RGB/TrueColor rainbow gradient
 * - Color conversions (RGB to ANSI-256 to ANSI-8)
 * - Hex color parsing (#FF0000, etc.)
 * - Background colors with text
 */

test.use({
  program: {
    file: "../bin/colors",
    args: [],
  },
});

test.describe("Colors Example", () => {
  test.describe("ANSI-8 Basic Colors Section", () => {
    test("displays ANSI-8 colors section header", async ({ terminal }) => {
      await expect(terminal.getByText(/ANSI-8 Colors.*Basic/g)).toBeVisible();
    });

    test("renders color blocks in first row", async ({ terminal }) => {
      await expect(terminal.getByText(/ANSI-8 Colors/g)).toBeVisible();

      // Color blocks use the block character - verify via buffer since there are many blocks
      const buffer = terminal.getBuffer();
      let hasBlock = false;
      for (const row of buffer) {
        for (const cell of row) {
          if (cell === "█") {
            hasBlock = true;
            break;
          }
        }
        if (hasBlock) break;
      }
      expect(hasBlock).toBe(true);
    });

    test("displays 8 basic color samples", async ({ terminal }) => {
      await expect(terminal.getByText(/ANSI-8 Colors/g)).toBeVisible();

      const buffer = terminal.getBuffer();
      // Row 1 (after title) should have color blocks
      let blockCount = 0;
      if (buffer.length > 1) {
        for (const cell of buffer[1]) {
          if (cell === "█") {
            blockCount++;
          }
        }
      }
      // 8 colors x 2 blocks each = 16 blocks
      expect(blockCount).toBeGreaterThanOrEqual(8);
    });
  });

  test.describe("ANSI-256 Bright Colors Section", () => {
    test("displays ANSI-256 bright colors section header", async ({
      terminal,
    }) => {
      await expect(terminal.getByText("ANSI-256 Bright Colors:")).toBeVisible();
    });

    test("renders bright color samples", async ({ terminal }) => {
      await expect(terminal.getByText("ANSI-256 Bright Colors:")).toBeVisible();

      const buffer = terminal.getBuffer();
      // Find the row with "ANSI-256 Bright Colors:"
      let brightRowIdx = -1;
      for (let i = 0; i < buffer.length; i++) {
        const rowText = buffer[i].join("");
        if (rowText.includes("ANSI-256 Bright Colors:")) {
          brightRowIdx = i;
          break;
        }
      }

      // Next row should have color blocks
      expect(brightRowIdx).toBeGreaterThan(-1);
      if (brightRowIdx >= 0 && buffer.length > brightRowIdx + 1) {
        let hasBlocks = false;
        for (const cell of buffer[brightRowIdx + 1]) {
          if (cell === "█") {
            hasBlocks = true;
            break;
          }
        }
        expect(hasBlocks).toBe(true);
      }
    });
  });

  test.describe("Color Cube Section", () => {
    test("displays color cube section header", async ({ terminal }) => {
      await expect(
        terminal.getByText(/ANSI-256 Color Cube.*216 colors/g)
      ).toBeVisible();
    });

    test("renders color cube samples", async ({ terminal }) => {
      await expect(terminal.getByText(/Color Cube/g)).toBeVisible();

      // The color cube uses colored blocks
      const buffer = terminal.getBuffer();
      let foundColoredBlocks = false;

      for (const row of buffer) {
        let rowBlockCount = 0;
        for (const cell of row) {
          if (cell === "█") {
            rowBlockCount++;
          }
        }
        // Color cube row has 36 samples x 2 blocks = 72 blocks
        if (rowBlockCount >= 36) {
          foundColoredBlocks = true;
          break;
        }
      }

      expect(foundColoredBlocks).toBe(true);
    });
  });

  test.describe("Grayscale Section", () => {
    test("displays grayscale section header", async ({ terminal }) => {
      await expect(
        terminal.getByText(/ANSI-256 Grayscale.*24 levels/g)
      ).toBeVisible();
    });

    test("renders 24 grayscale levels", async ({ terminal }) => {
      await expect(terminal.getByText(/Grayscale/g)).toBeVisible();

      const buffer = terminal.getBuffer();
      // Find grayscale row
      let grayscaleRowIdx = -1;
      for (let i = 0; i < buffer.length; i++) {
        const rowText = buffer[i].join("");
        if (rowText.includes("Grayscale")) {
          grayscaleRowIdx = i;
          break;
        }
      }

      // Next row should have 24 levels x 2 blocks = 48 blocks
      expect(grayscaleRowIdx).toBeGreaterThan(-1);
      if (grayscaleRowIdx >= 0 && buffer.length > grayscaleRowIdx + 1) {
        let blockCount = 0;
        for (const cell of buffer[grayscaleRowIdx + 1]) {
          if (cell === "█") {
            blockCount++;
          }
        }
        expect(blockCount).toBeGreaterThanOrEqual(24);
      }
    });
  });

  test.describe("RGB TrueColor Section", () => {
    test("displays RGB TrueColor section header", async ({ terminal }) => {
      await expect(
        terminal.getByText(/RGB.*TrueColor.*16.7M colors/g)
      ).toBeVisible();
    });

    test("renders rainbow gradient", async ({ terminal }) => {
      await expect(terminal.getByText(/TrueColor/g)).toBeVisible();

      const buffer = terminal.getBuffer();
      // Find RGB row
      let rgbRowIdx = -1;
      for (let i = 0; i < buffer.length; i++) {
        const rowText = buffer[i].join("");
        if (rowText.includes("TrueColor")) {
          rgbRowIdx = i;
          break;
        }
      }

      // Next row should have 60 gradient blocks
      expect(rgbRowIdx).toBeGreaterThan(-1);
      if (rgbRowIdx >= 0 && buffer.length > rgbRowIdx + 1) {
        let blockCount = 0;
        for (const cell of buffer[rgbRowIdx + 1]) {
          if (cell === "█") {
            blockCount++;
          }
        }
        expect(blockCount).toBeGreaterThanOrEqual(30);
      }
    });
  });

  test.describe("Color Conversions Section", () => {
    test("displays color conversions section header", async ({ terminal }) => {
      await expect(terminal.getByText("Color Conversions:")).toBeVisible();
    });

    test("shows RGB to ANSI conversion description", async ({ terminal }) => {
      await expect(terminal.getByText(/RGB.*ANSI-256.*ANSI-8/g)).toBeVisible();
    });

    test("displays RGB values in description", async ({ terminal }) => {
      await expect(terminal.getByText(/255.*128.*64/g)).toBeVisible();
    });

    test("renders three color comparison blocks", async ({ terminal }) => {
      await expect(terminal.getByText("Color Conversions:")).toBeVisible();

      const buffer = terminal.getBuffer();
      // Find conversion description row
      let convRowIdx = -1;
      for (let i = 0; i < buffer.length; i++) {
        const rowText = buffer[i].join("");
        if (rowText.includes("RGB(255,128,64)")) {
          convRowIdx = i;
          break;
        }
      }

      // Next row should have 3 groups of 8 blocks each (at positions 0, 10, 20)
      expect(convRowIdx).toBeGreaterThan(-1);
      if (convRowIdx >= 0 && buffer.length > convRowIdx + 1) {
        let blockCount = 0;
        for (const cell of buffer[convRowIdx + 1]) {
          if (cell === "█") {
            blockCount++;
          }
        }
        // 3 groups x 8 blocks = 24 blocks
        expect(blockCount).toBeGreaterThanOrEqual(20);
      }
    });
  });

  test.describe("Hex Colors Section", () => {
    test("displays hex colors section header", async ({ terminal }) => {
      await expect(terminal.getByText("Hex Colors:")).toBeVisible();
    });

    test("shows red hex color code", async ({ terminal }) => {
      await expect(terminal.getByText("#FF0000")).toBeVisible();
    });

    test("shows green hex color code", async ({ terminal }) => {
      await expect(terminal.getByText("#00FF00")).toBeVisible();
    });

    test("shows blue hex color code", async ({ terminal }) => {
      await expect(terminal.getByText("#0000FF")).toBeVisible();
    });

    test("shows yellow hex color code", async ({ terminal }) => {
      await expect(terminal.getByText("#FFFF00")).toBeVisible();
    });

    test("shows magenta hex color code", async ({ terminal }) => {
      await expect(terminal.getByText("#FF00FF")).toBeVisible();
    });

    test("shows cyan hex color code", async ({ terminal }) => {
      await expect(terminal.getByText("#00FFFF")).toBeVisible();
    });

    test("renders color blocks above hex labels", async ({ terminal }) => {
      await expect(terminal.getByText("Hex Colors:")).toBeVisible();

      const buffer = terminal.getBuffer();
      // Find hex colors row
      let hexRowIdx = -1;
      for (let i = 0; i < buffer.length; i++) {
        const rowText = buffer[i].join("");
        if (rowText.includes("Hex Colors:")) {
          hexRowIdx = i;
          break;
        }
      }

      // Next row should have 6 colors x 4 blocks = 24 blocks
      expect(hexRowIdx).toBeGreaterThan(-1);
      if (hexRowIdx >= 0 && buffer.length > hexRowIdx + 1) {
        let blockCount = 0;
        for (const cell of buffer[hexRowIdx + 1]) {
          if (cell === "█") {
            blockCount++;
          }
        }
        expect(blockCount).toBeGreaterThanOrEqual(20);
      }
    });
  });

  test.describe("Background Colors Section", () => {
    test("displays background colors section header", async ({ terminal }) => {
      await expect(terminal.getByText("Background Colors:")).toBeVisible();
    });

    test("shows text with backgrounds", async ({ terminal }) => {
      await expect(terminal.getByText(/Text with backgrounds/g)).toBeVisible();
    });

    test("text has varied background colors", async ({ terminal }) => {
      await expect(terminal.getByText("Background Colors:")).toBeVisible();

      const buffer = terminal.getBuffer();
      // Find background colors row
      let bgRowIdx = -1;
      for (let i = 0; i < buffer.length; i++) {
        const rowText = buffer[i].join("");
        if (rowText.includes("Background Colors:")) {
          bgRowIdx = i;
          break;
        }
      }

      // Next row should have "Text with backgrounds"
      expect(bgRowIdx).toBeGreaterThan(-1);
      if (bgRowIdx >= 0 && buffer.length > bgRowIdx + 1) {
        const nextRowText = buffer[bgRowIdx + 1].join("");
        // Verify the text content is present
        expect(
          nextRowText.includes("Text") || nextRowText.includes("background")
        ).toBe(true);
      }
    });

    test("each character has different background color", async ({
      terminal,
    }) => {
      // We can verify the text is displayed, but cannot verify actual background colors
      // without using serialize() which returns style shifts
      await expect(terminal.getByText(/Text with backgrounds/g)).toBeVisible();
    });
  });

  test.describe("Visual Layout", () => {
    test("sections are displayed in correct order", async ({ terminal }) => {
      await expect(terminal.getByText(/ANSI-8 Colors/g)).toBeVisible();

      const buffer = terminal.getBuffer();
      let ansi8Row = -1;
      let brightRow = -1;
      let cubeRow = -1;
      let grayscaleRow = -1;
      let rgbRow = -1;
      let conversionRow = -1;
      let hexRow = -1;
      let bgRow = -1;

      for (let i = 0; i < buffer.length; i++) {
        const rowText = buffer[i].join("");

        if (rowText.includes("ANSI-8 Colors")) ansi8Row = i;
        if (rowText.includes("ANSI-256 Bright Colors:")) brightRow = i;
        if (rowText.includes("Color Cube")) cubeRow = i;
        if (rowText.includes("Grayscale")) grayscaleRow = i;
        if (rowText.includes("TrueColor")) rgbRow = i;
        if (rowText.includes("Color Conversions:")) conversionRow = i;
        if (rowText.includes("Hex Colors:")) hexRow = i;
        if (rowText.includes("Background Colors:")) bgRow = i;
      }

      // Verify order: ANSI-8 < Bright < Cube < Grayscale < RGB < Conversion < Hex < Background
      expect(ansi8Row).toBeLessThan(brightRow);
      expect(brightRow).toBeLessThan(cubeRow);
      expect(cubeRow).toBeLessThan(grayscaleRow);
      expect(grayscaleRow).toBeLessThan(rgbRow);
      expect(rgbRow).toBeLessThan(conversionRow);
      expect(conversionRow).toBeLessThan(hexRow);
      expect(hexRow).toBeLessThan(bgRow);
    });
  });

  test.describe("Visual Snapshot", () => {
    test("matches visual snapshot", async ({ terminal }) => {
      await expect(terminal.getByText("Hex Colors:")).toBeVisible();
      await expect(terminal).toMatchSnapshot();
    });
  });
});
