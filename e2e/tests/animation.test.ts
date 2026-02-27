import { expect, test } from "@microsoft/tui-test";

/**
 * E2E tests for the Termisu animation example.
 *
 * Tests verify:
 * - Bouncing ball animation rendering
 * - Timer type display (Timer or SystemTimer)
 * - FPS stats display (target/actual)
 * - Controls bar with quit instructions
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
    test("displays timer type header", async ({ terminal }) => {
      // Default starts with sleep-based timer
      await expect(terminal.getByText(/Timer \(sleep-based\)/g)).toBeVisible();
    });

    test("displays target FPS", async ({ terminal }) => {
      // Shows target FPS (default 60fps)
      await expect(terminal.getByText(/Target: \d+fps/g)).toBeVisible();
    });

    test("displays actual FPS", async ({ terminal }) => {
      // FPS may show as integer (60fps) or float (60.0fps)
      await expect(terminal.getByText(/Actual: \d+\.?\d*fps/g)).toBeVisible();
    });

    test("shows quit hint in controls bar", async ({ terminal }) => {
      await expect(terminal.getByText(/Q=quit/g)).toBeVisible();
    });

    test("renders bouncing ball character", async ({ terminal }) => {
      await expect(terminal.getByText("●")).toBeVisible();
    });

    test("displays controls bar with timer toggle", async ({ terminal }) => {
      await expect(terminal.getByText(/T=timer/g)).toBeVisible();
    });
  });

  test.describe("Stats Display", () => {
    test("shows target FPS with interval", async ({ terminal }) => {
      // Format: "Target: 60fps (16.7ms)"
      await expect(
        terminal.getByText(/Target: \d+fps \(\d+\.?\d*ms\)/g)
      ).toBeVisible();
    });

    test("shows actual FPS with delta", async ({ terminal }) => {
      // Format: "Actual: 60.0fps (16.5ms)" - FPS may be int or float
      await expect(
        terminal.getByText(/Actual: \d+\.?\d*fps \(\d+\.?\d*ms\)/g)
      ).toBeVisible();
    });

    test("status line uses pipe separators", async ({ terminal }) => {
      // Format: "Target: ... | Actual: ..."
      await expect(terminal.getByText(/Target:.*\|.*Actual:/g)).toBeVisible();
    });
  });

  test.describe("Controls Bar", () => {
    test("shows timer toggle control", async ({ terminal }) => {
      await expect(terminal.getByText(/T=timer/g)).toBeVisible();
    });

    test("shows FPS change controls", async ({ terminal }) => {
      await expect(terminal.getByText(/←→=FPS/g)).toBeVisible();
    });

    test("shows pause control", async ({ terminal }) => {
      await expect(terminal.getByText(/SPACE=pause/g)).toBeVisible();
    });

    test("shows speed control", async ({ terminal }) => {
      await expect(terminal.getByText(/\+\/-=speed/g)).toBeVisible();
    });

    test("shows record control", async ({ terminal }) => {
      await expect(terminal.getByText(/R=record/g)).toBeVisible();
    });

    test("shows quit control", async ({ terminal }) => {
      await expect(terminal.getByText(/Q=quit/g)).toBeVisible();
    });
  });

  test.describe("Animation Progression", () => {
    test("animation updates over time", async ({ terminal }) => {
      // Wait for initial render
      await expect(terminal.getByText(/Target: \d+fps/g)).toBeVisible();

      // Extract ball position from buffer
      const getBallPosition = (): { x: number; y: number } | null => {
        const buffer = terminal.getBuffer();
        for (let y = 0; y < buffer.length; y++) {
          const text = buffer[y].join("");
          const x = text.indexOf("●");
          if (x !== -1) return { x, y };
        }
        return null;
      };

      const initialPos = getBallPosition();
      expect(initialPos).not.toBeNull();

      // Poll until ball moves (more reliable than fixed timeout)
      let newPos = initialPos;
      const maxWait = 2000; // 2 second max wait
      const pollInterval = 50;
      let elapsed = 0;

      while (
        newPos?.x === initialPos?.x &&
        newPos?.y === initialPos?.y &&
        elapsed < maxWait
      ) {
        await new Promise((resolve) => setTimeout(resolve, pollInterval));
        elapsed += pollInterval;
        newPos = getBallPosition();
      }

      // Animation should have moved the ball
      expect(
        newPos?.x !== initialPos?.x || newPos?.y !== initialPos?.y
      ).toBeTruthy();
    });
  });

  test.describe("Exit Handling", () => {
    test("exits gracefully on 'q' key", async ({ terminal }) => {
      await expect(terminal.getByText(/Q=quit/g)).toBeVisible();
      terminal.write("q");
      // Terminal should close - test completes successfully if no hang
    });

    test("exits gracefully on ESC key", async ({ terminal }) => {
      await expect(terminal.getByText(/Q=quit/g)).toBeVisible();
      terminal.keyEscape();
      // Terminal should close - test completes successfully if no hang
    });

    test("does not exit on other keys", async ({ terminal }) => {
      await expect(terminal.getByText(/Q=quit/g)).toBeVisible();
      terminal.write("x");
      // Animation should continue running
      await expect(terminal.getByText(/Q=quit/g)).toBeVisible();
    });
  });

  test.describe("Ball Display", () => {
    test("ball character is visible", async ({ terminal }) => {
      await expect(terminal.getByText("●")).toBeVisible();
    });

    test("ball rendered with animation active", async ({ terminal }) => {
      // Verify animation is running by checking stats (FPS may be int or float)
      await expect(terminal.getByText(/Actual: \d+\.?\d*fps/g)).toBeVisible();
      // Verify the ball exists
      await expect(terminal.getByText("●")).toBeVisible();
    });
  });

  // Note: Visual snapshot test disabled for animation
  // Animation content changes every frame, making snapshots unreliable
});
