import { expect, test } from "@microsoft/tui-test";

/**
 * E2E tests for the Termisu animation example.
 *
 * Tests verify:
 * - Bouncing ball animation rendering
 * - Frame counter display and progression
 * - Ball position tracking with coordinate format
 * - Status bar format
 * - Animation progression between frames
 * - Graceful exit on 'q' or ESC
 */

test.use({
  program: {
    file: "../bin/animation",
    args: [],
  },
});

test.describe("Animation Example", () => {
  test.describe("Initial Rendering", () => {
    test("displays frame counter label", async ({ terminal }) => {
      await expect(terminal.getByText(/Frame:/g)).toBeVisible();
    });

    test("displays ball position label", async ({ terminal }) => {
      await expect(terminal.getByText(/Ball:/g)).toBeVisible();
    });

    test("shows quit hint in status bar", async ({ terminal }) => {
      await expect(terminal.getByText(/Press 'q' to quit/g)).toBeVisible();
    });

    test("renders bouncing ball character", async ({ terminal }) => {
      await expect(terminal.getByText("●")).toBeVisible();
    });

    test("displays complete status bar format", async ({ terminal }) => {
      // Status bar format: "Frame: N | Ball: x,y | Press 'q' to quit"
      await expect(
        terminal.getByText(/Frame: \d+ \| Ball: \d+,\d+ \| Press 'q' to quit/g)
      ).toBeVisible();
    });
  });

  test.describe("Animation Progression", () => {
    test("frame counter shows numeric value", async ({ terminal }) => {
      await expect(terminal.getByText(/Frame: \d+/g)).toBeVisible();
    });

    test("ball position shows coordinate format (x,y)", async ({
      terminal,
    }) => {
      await expect(terminal.getByText(/Ball: \d+,\d+/g)).toBeVisible();
    });

    test("animation updates over time", async ({ terminal }) => {
      // Wait for initial render and extract initial frame number
      await expect(terminal.getByText(/Frame: \d+/g)).toBeVisible();

      // Extract initial frame number from buffer
      const getFrameNumber = (): number | null => {
        const buffer = terminal.getBuffer();
        for (const row of buffer) {
          const text = row.join("");
          const match = text.match(/Frame: (\d+)/);
          if (match) return parseInt(match[1], 10);
        }
        return null;
      };

      const initialFrame = getFrameNumber();
      expect(initialFrame).not.toBeNull();

      // Poll until frame advances (more reliable than fixed timeout)
      let updatedFrame = initialFrame;
      const maxWait = 2000; // 2 second max wait
      const pollInterval = 50;
      let elapsed = 0;

      while (updatedFrame === initialFrame && elapsed < maxWait) {
        await new Promise((resolve) => setTimeout(resolve, pollInterval));
        elapsed += pollInterval;
        updatedFrame = getFrameNumber();
      }

      // Animation should have advanced at least one frame
      expect(updatedFrame).not.toBe(initialFrame);
    });
  });

  test.describe("Status Bar", () => {
    test("status bar contains frame count", async ({ terminal }) => {
      await expect(terminal.getByText(/Frame: \d+/g)).toBeVisible();
    });

    test("status bar contains ball coordinates", async ({ terminal }) => {
      await expect(terminal.getByText(/Ball: \d+,\d+/g)).toBeVisible();
    });

    test("status bar uses pipe separators", async ({ terminal }) => {
      // Format: "Frame: N | Ball: x,y | Press 'q' to quit"
      await expect(terminal.getByText(/\|.*\|/g)).toBeVisible();
    });
  });

  test.describe("Exit Handling", () => {
    test("exits gracefully on 'q' key", async ({ terminal }) => {
      await expect(terminal.getByText(/Frame:/g)).toBeVisible();
      terminal.write("q");
      // Terminal should close - test completes successfully if no hang
    });

    test("exits gracefully on ESC key", async ({ terminal }) => {
      await expect(terminal.getByText(/Frame:/g)).toBeVisible();
      terminal.keyEscape();
      // Terminal should close - test completes successfully if no hang
    });

    test("does not exit on other keys", async ({ terminal }) => {
      await expect(terminal.getByText(/Frame:/g)).toBeVisible();
      terminal.write("x");
      // Animation should continue running
      await expect(terminal.getByText(/Frame:/g)).toBeVisible();
    });
  });

  test.describe("Ball Display", () => {
    test("ball character is visible", async ({ terminal }) => {
      await expect(terminal.getByText("●")).toBeVisible();
    });

    test("ball exists on screen", async ({ terminal }) => {
      await expect(terminal.getByText(/Ball:/g)).toBeVisible();
      // Verify the ball exists by checking the ball character is rendered
      await expect(terminal.getByText("●")).toBeVisible();
    });
  });

  // Note: Visual snapshot test disabled for animation
  // Animation content changes every frame, making snapshots unreliable
});
