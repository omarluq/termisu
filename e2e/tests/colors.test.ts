import { expect, test } from "@microsoft/tui-test";

/**
 * E2E tests for the Termisu colors example.
 *
 * Tests verify:
 * - ANSI-8 basic colors
 * - ANSI-256 bright colors
 * - Color cube and grayscale
 * - RGB/TrueColor gradients
 * - Color conversions
 * - Hex color parsing
 * - Background colors
 */

test.use({
  program: {
    file: "../bin/colors",
    args: [],
  },
});

test.describe("Colors Example", () => {
  test("displays ANSI-8 colors section", async ({ terminal }) => {
    await expect(terminal.getByText(/ANSI-8 Colors.*Basic/g)).toBeVisible();
  });

  test("displays ANSI-256 bright colors section", async ({ terminal }) => {
    await expect(terminal.getByText("ANSI-256 Bright Colors:")).toBeVisible();
  });

  test("displays color cube section", async ({ terminal }) => {
    await expect(
      terminal.getByText(/ANSI-256 Color Cube.*216 colors/g)
    ).toBeVisible();
  });

  test("displays grayscale section", async ({ terminal }) => {
    await expect(
      terminal.getByText(/ANSI-256 Grayscale.*24 levels/g)
    ).toBeVisible();
  });

  test("displays RGB TrueColor section", async ({ terminal }) => {
    await expect(
      terminal.getByText(/RGB.*TrueColor.*16.7M colors/g)
    ).toBeVisible();
  });

  test("displays color conversions section", async ({ terminal }) => {
    await expect(terminal.getByText("Color Conversions:")).toBeVisible();
  });

  test("displays hex colors section", async ({ terminal }) => {
    await expect(terminal.getByText("Hex Colors:")).toBeVisible();
  });

  test("displays background colors section", async ({ terminal }) => {
    await expect(terminal.getByText("Background Colors:")).toBeVisible();
  });

  test("matches visual snapshot", async ({ terminal }) => {
    await expect(terminal.getByText("Hex Colors:")).toBeVisible();
    await expect(terminal).toMatchSnapshot();
  });
});
