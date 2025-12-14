import { defineConfig } from "@microsoft/tui-test";

export default defineConfig({
  // Retry failed tests up to 2 times for flaky mitigation
  retries: 2,

  // Enable tracing for debugging failures
  trace: true,

  // Test timeout in milliseconds
  timeout: 30_000,

  // Trace output folder
  traceFolder: "tui-traces",

  // Terminal dimensions for consistent testing
  // Showcase demo needs ~45 rows for full content
  use: {
    rows: 50,
    columns: 100,
  },
});
