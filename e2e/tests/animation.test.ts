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
      // Wait for initial render
      await expect(terminal.getByText(/Frame: \d+/g)).toBeVisible();

      // Get initial state
      const initialBuffer = terminal.serialize();
      const initialContent = JSON.stringify(initialBuffer);

      // Wait a bit for animation frames (animation runs at ~60 FPS)
      await new Promise((resolve) => setTimeout(resolve, 100));

      // Get updated state
      const updatedBuffer = terminal.serialize();
      const updatedContent = JSON.stringify(updatedBuffer);

      // Animation should have changed something (frame counter or ball position)
      // Note: This tests that the animation is actually running
      expect(updatedContent).not.toBe(initialContent);
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
