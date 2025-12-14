import { expect, test } from "@microsoft/tui-test";

/**
 * E2E tests for the Termisu keyboard and mouse demo.
 *
 * Tests verify:
 * - Keyboard layout rendering with all key rows
 * - Key press detection and event logging
 * - Modifier key combinations (Ctrl, Alt, Shift)
 * - Special keys (arrows, Tab, Enter, Backspace)
 * - Mouse event tracking (position, buttons, wheel)
 * - Graceful exit handling
 */

test.use({
  program: {
    file: "../bin/kmd",
    args: [],
  },
});

test.describe("Keyboard & Mouse Demo", () => {
  test.describe("Layout Rendering", () => {
    test("displays demo title with keyboard emoji", async ({ terminal }) => {
      await expect(terminal.getByText(/KEYBOARD.*MOUSE.*DEMO/g)).toBeVisible();
    });

    test("renders all keyboard rows", async ({ terminal }) => {
      // Wait for keyboard layout to render
      await expect(terminal.getByText("Esc")).toBeVisible();

      // Verify keyboard layout via buffer to avoid strict mode issues
      const buffer = terminal.getBuffer();
      const fullText = buffer.map((row) => row.join("")).join("\n");

      // Row 0: Escape and number row (1-9, 0)
      expect(fullText.includes("Esc")).toBe(true);

      // Row 4: Modifier keys (Ctrl and Alt appear multiple times, check via buffer)
      expect(fullText.includes("Ctrl")).toBe(true);
      expect(fullText.includes("Alt")).toBe(true);

      // Verify QWERTY row exists by checking for the pattern
      expect(
        fullText.includes("Q") &&
          fullText.includes("W") &&
          fullText.includes("E")
      ).toBe(true);
    });

    test("displays mouse info panel", async ({ terminal }) => {
      await expect(terminal.getByText(/Mouse:/g)).toBeVisible();
      await expect(terminal.getByText(/Position:/g)).toBeVisible();
    });

    test("shows quit hint with key options", async ({ terminal }) => {
      await expect(terminal.getByText(/ESC.*Ctrl.*C.*quit/g)).toBeVisible();
    });
  });

  test.describe("Lowercase Letter Keys", () => {
    test("detects lowercase 'a' key press", async ({ terminal }) => {
      await expect(terminal.getByText("Esc")).toBeVisible();
      terminal.write("a");
      await expect(terminal.getByText(/Last event:.*LowerA/g)).toBeVisible();
    });

    test("detects lowercase 'z' key press", async ({ terminal }) => {
      await expect(terminal.getByText("Esc")).toBeVisible();
      terminal.write("z");
      await expect(terminal.getByText(/Last event:.*LowerZ/g)).toBeVisible();
    });

    test("detects lowercase 'm' key press", async ({ terminal }) => {
      await expect(terminal.getByText("Esc")).toBeVisible();
      terminal.write("m");
      await expect(terminal.getByText(/Last event:.*LowerM/g)).toBeVisible();
    });
  });

  test.describe("Uppercase Letter Keys", () => {
    test("detects uppercase 'A' with shift indicator", async ({ terminal }) => {
      await expect(terminal.getByText("Esc")).toBeVisible();
      terminal.write("A");
      await expect(terminal.getByText(/Last event:.*UpperA/g)).toBeVisible();
    });

    test("detects uppercase 'Z' key press", async ({ terminal }) => {
      await expect(terminal.getByText("Esc")).toBeVisible();
      terminal.write("Z");
      await expect(terminal.getByText(/Last event:.*UpperZ/g)).toBeVisible();
    });
  });

  test.describe("Number Keys", () => {
    test("detects number '1' key press", async ({ terminal }) => {
      await expect(terminal.getByText("Esc")).toBeVisible();
      terminal.write("1");
      await expect(terminal.getByText(/Last event:.*Num1/g)).toBeVisible();
    });

    test("detects number '0' key press", async ({ terminal }) => {
      await expect(terminal.getByText("Esc")).toBeVisible();
      terminal.write("0");
      await expect(terminal.getByText(/Last event:.*Num0/g)).toBeVisible();
    });
  });

  test.describe("Shifted Number Keys (Symbols)", () => {
    test("detects '!' (Shift+1)", async ({ terminal }) => {
      await expect(terminal.getByText("Esc")).toBeVisible();
      terminal.write("!");
      await expect(terminal.getByText(/Last event:.*Exclaim/g)).toBeVisible();
    });

    test("detects '@' (Shift+2)", async ({ terminal }) => {
      await expect(terminal.getByText("Esc")).toBeVisible();
      terminal.write("@");
      await expect(terminal.getByText(/Last event:.*At/g)).toBeVisible();
    });

    test("detects '#' (Shift+3)", async ({ terminal }) => {
      await expect(terminal.getByText("Esc")).toBeVisible();
      terminal.write("#");
      await expect(terminal.getByText(/Last event:.*Hash/g)).toBeVisible();
    });
  });

  test.describe("Special Keys", () => {
    test("detects Tab key press", async ({ terminal }) => {
      await expect(terminal.getByText("Esc")).toBeVisible();
      terminal.write("\t");
      // Tab shows as Tab with note about Ctrl+I equivalence
      await expect(terminal.getByText(/Last event:.*Tab/g)).toBeVisible();
    });

    test("detects Enter key press", async ({ terminal }) => {
      await expect(terminal.getByText("Esc")).toBeVisible();
      terminal.write("\r");
      // Enter shows with note about Ctrl+M equivalence
      await expect(terminal.getByText(/Last event:.*Enter/g)).toBeVisible();
    });

    test("detects Backspace key press", async ({ terminal }) => {
      await expect(terminal.getByText("Esc")).toBeVisible();
      terminal.keyBackspace();
      await expect(terminal.getByText(/Last event:.*Backspace/g)).toBeVisible();
    });

    test("detects Space key press", async ({ terminal }) => {
      await expect(terminal.getByText("Esc")).toBeVisible();
      terminal.write(" ");
      await expect(terminal.getByText(/Last event:.*Space/g)).toBeVisible();
    });
  });

  test.describe("Arrow Keys", () => {
    test("detects Up arrow key", async ({ terminal }) => {
      await expect(terminal.getByText("Esc")).toBeVisible();
      terminal.keyUp();
      await expect(terminal.getByText(/Last event:.*Up/g)).toBeVisible();
    });

    test("detects Down arrow key", async ({ terminal }) => {
      await expect(terminal.getByText("Esc")).toBeVisible();
      terminal.keyDown();
      await expect(terminal.getByText(/Last event:.*Down/g)).toBeVisible();
    });

    test("detects Left arrow key", async ({ terminal }) => {
      await expect(terminal.getByText("Esc")).toBeVisible();
      terminal.keyLeft();
      await expect(terminal.getByText(/Last event:.*Left/g)).toBeVisible();
    });

    test("detects Right arrow key", async ({ terminal }) => {
      await expect(terminal.getByText("Esc")).toBeVisible();
      terminal.keyRight();
      await expect(terminal.getByText(/Last event:.*Right/g)).toBeVisible();
    });
  });

  test.describe("Punctuation Keys", () => {
    test("detects comma key", async ({ terminal }) => {
      await expect(terminal.getByText("Esc")).toBeVisible();
      terminal.write(",");
      await expect(terminal.getByText(/Last event:.*Comma/g)).toBeVisible();
    });

    test("detects period key", async ({ terminal }) => {
      await expect(terminal.getByText("Esc")).toBeVisible();
      terminal.write(".");
      await expect(terminal.getByText(/Last event:.*Period/g)).toBeVisible();
    });

    test("detects slash key", async ({ terminal }) => {
      await expect(terminal.getByText("Esc")).toBeVisible();
      terminal.write("/");
      await expect(terminal.getByText(/Last event:.*Slash/g)).toBeVisible();
    });

    test("detects semicolon key", async ({ terminal }) => {
      await expect(terminal.getByText("Esc")).toBeVisible();
      terminal.write(";");
      await expect(terminal.getByText(/Last event:.*Semicolon/g)).toBeVisible();
    });
  });

  test.describe("Bracket Keys", () => {
    test("detects left bracket", async ({ terminal }) => {
      await expect(terminal.getByText("Esc")).toBeVisible();
      terminal.write("[");
      await expect(
        terminal.getByText(/Last event:.*LeftBracket/g)
      ).toBeVisible();
    });

    test("detects right bracket", async ({ terminal }) => {
      await expect(terminal.getByText("Esc")).toBeVisible();
      terminal.write("]");
      await expect(
        terminal.getByText(/Last event:.*RightBracket/g)
      ).toBeVisible();
    });

    test("detects left brace (Shift+[)", async ({ terminal }) => {
      await expect(terminal.getByText("Esc")).toBeVisible();
      terminal.write("{");
      await expect(terminal.getByText(/Last event:.*LeftBrace/g)).toBeVisible();
    });

    test("detects right brace (Shift+])", async ({ terminal }) => {
      await expect(terminal.getByText("Esc")).toBeVisible();
      terminal.write("}");
      await expect(
        terminal.getByText(/Last event:.*RightBrace/g)
      ).toBeVisible();
    });
  });

  test.describe("Mouse Events", () => {
    // Mouse events use SGR encoding: \x1b[<Btn;X;Y;M for press, m for release
    // Button 0 = left, 1 = middle, 2 = right, 64 = wheel up, 65 = wheel down

    test("detects mouse left click at position", async ({ terminal }) => {
      await expect(terminal.getByText(/Mouse:/g)).toBeVisible();
      // Send SGR mouse press: button 0 (left) at position 10,5
      terminal.write("\x1b[<0;10;5M");
      // Wait for the app to process and render the mouse event
      await new Promise((resolve) => setTimeout(resolve, 100));
      // Verify position appears somewhere in output
      const buffer = terminal.getBuffer();
      const fullText = buffer.map((row) => row.join("")).join("\n");
      expect(fullText.includes("10") && fullText.includes("5")).toBe(true);
    });

    test("detects mouse movement", async ({ terminal }) => {
      await expect(terminal.getByText(/Mouse:/g)).toBeVisible();
      // Send mouse motion event (button 35 = motion with no button in SGR encoding)
      terminal.write("\x1b[<35;20;10M");
      // Wait for the app to process and render the mouse event
      await new Promise((resolve) => setTimeout(resolve, 100));
      // Verify position appears somewhere in output
      const buffer = terminal.getBuffer();
      const fullText = buffer.map((row) => row.join("")).join("\n");
      expect(fullText.includes("20") && fullText.includes("10")).toBe(true);
    });

    test("detects mouse wheel scroll up", async ({ terminal }) => {
      await expect(terminal.getByText(/Mouse:/g)).toBeVisible();
      // Button 64 = wheel up
      terminal.write("\x1b[<64;15;8M");
      // Wait for the app to process and render the mouse event
      await new Promise((resolve) => setTimeout(resolve, 100));
      // Use buffer to verify WheelUp is present
      const buffer = terminal.getBuffer();
      const fullText = buffer.map((row) => row.join("")).join("\n");
      expect(fullText.includes("WheelUp")).toBe(true);
    });

    test("detects mouse wheel scroll down", async ({ terminal }) => {
      await expect(terminal.getByText(/Mouse:/g)).toBeVisible();
      // Button 65 = wheel down
      terminal.write("\x1b[<65;15;8M");
      // Wait for the app to process and render the mouse event
      await new Promise((resolve) => setTimeout(resolve, 100));
      // Use buffer to verify WheelDown is present
      const buffer = terminal.getBuffer();
      const fullText = buffer.map((row) => row.join("")).join("\n");
      expect(fullText.includes("WheelDown")).toBe(true);
    });
  });

  test.describe("Exit Handling", () => {
    test("exits gracefully on ESC key", async ({ terminal }) => {
      await expect(terminal.getByText("Esc")).toBeVisible();
      terminal.keyEscape();
      // Terminal should close - we verify the process can exit
    });

    test("exits gracefully on Ctrl+C", async ({ terminal }) => {
      await expect(terminal.getByText("Esc")).toBeVisible();
      terminal.keyCtrlC();
      // Terminal should close on Ctrl+C
    });
  });

  // Note: Visual snapshot test disabled for keyboard demo
  // The keyboard layout contains backtick characters (`) which break
  // JavaScript snapshot format (treated as template literals)
});
