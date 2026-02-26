# Phase 05: Regression Tests and Final Verification

This phase adds targeted regression tests for every bug fixed in Phases 1-4, runs the full suite, and performs a final validation pass. The goal is to ensure each fix is covered by at least one spec that would catch a regression, and that the full test suite passes clean. This also updates the codex-bug-findings.md to mark all 10 bugs as closed.

## Tasks

- [x] **Add regression spec for BUG-001 (sync update ensure safety).** Create or extend specs in `spec/termisu/terminal_spec.cr` (or the appropriate spec file for Terminal rendering) that verify:
  - When `@sync_updates` is enabled and `render_to`/`sync_to` raises, the `end_sync_update` sequence is still emitted
  - Use a mock renderer that raises during render and verify BSU/ESU pairing via captured output
  - At minimum, verify that `render` and `sync` don't leave sync mode open on exception
  - **Done:** Added 4 regression tests in `spec/termisu/terminal/sync_update_spec.cr` under "exception safety (BUG-001 regression)". Uses `RaisingCaptureTerminal` subclass with `size` override (to ensure non-zero buffer in test envs) and `move_cursor` override that raises during `render_to`/`sync_to`. Tests verify: ESU emitted after render exception, ESU emitted after sync exception, flush occurs after exception, BSU/ESU counts are paired.

- [x] **Add regression specs for BUG-005 (EINTR retry), BUG-010 (high fd guard), and BUG-011 (poll timeout).** Write three focused specs:
  - BUG-005 in `spec/termisu/terminal/backend_spec.cr`: Verify that if a signal occurs during `Backend#read`, the retry loop handles it (this may be hard to test deterministically — at minimum test the happy path still works)
  - BUG-010 in `spec/termisu/reader_spec.cr`: Verify that creating a Reader with an fd >= 1024 either falls back to poll-based checking or raises a clear descriptive error (not an IndexError). You can simulate this with a pipe fd or by mocking the fd value.
  - BUG-011 in `spec/termisu/event/poller/poll_spec.cr`: Verify that `wait(20.milliseconds)` with an active timer (e.g., 200ms) returns nil within approximately 20-50ms, not 200ms. Use `Time.monotonic` to measure actual elapsed time.
  - **Done:** Added 13 regression tests across 3 spec files:
    - BUG-005: 5 tests in `spec/termisu/terminal/backend_spec.cr` — exercises EINTR retry happy path through Reader (same pattern as Backend#read) with pipe I/O, EOF handling, multi-byte reads, peek, and retry limit constant verification.
    - BUG-010: 5 tests in `spec/termisu/reader_spec.cr` under "high fd guard (BUG-010 regression)" — verifies FD_SETSIZE=1024, confirms fd=1024 and fd=2048 raise IOError (not IndexError) via poll fallback, verifies normal pipe fds use select path, and tests wait_for_data with high fd.
    - BUG-011: 3 tests in `spec/termisu/event/poller_spec.cr` under "user timeout respected with active timer (BUG-011 regression)" — verifies wait(20ms) returns nil within ~50ms despite 200ms timer, wait(10ms) returns quickly with multiple long timers, and timer fires before user timeout when timer is shorter.

- [x] **Add regression spec for BUG-002 (SIGWINCH non-blocking), BUG-006 (render cache reset), and BUG-007 (version fallback).** Write three focused specs:
  - BUG-002 in `spec/termisu/event/source/resize_spec.cr`: Verify that the resize source signal handler does not use blocking channel sends. If using Atomic flag approach, verify the flag is set on signal and processed in the loop. At minimum, verify resize events are still delivered correctly.
  - BUG-006 in `spec/termisu/terminal_spec.cr`: Verify that after `with_mode(mode, preserve_screen: true)`, the cached fg/bg/attr are reset to their initial nil/None state, so subsequent renders re-emit style sequences. Use a capture terminal to verify escape sequences are re-emitted after mode block.
  - BUG-007: Verify the VERSION constant is defined and non-empty. Verify VERSION_MAJOR, VERSION_MINOR, VERSION_PATCH are integers. These constants should now work regardless of shards availability since they parse shard.yml.
  - **Done:** Added 13 regression tests across 3 spec files:
    - BUG-002: 3 tests in `spec/termisu/event/source/resize_spec.cr` under "non-blocking signal handler (BUG-002 regression)" — verifies events delivered via polling without blocking, no deadlock with minimal channel capacity, and continued delivery after channel drain.
    - BUG-006: 4 tests in `spec/termisu/terminal_spec.cr` under "render cache reset after mode switch (BUG-006 regression)" — verifies foreground color re-emitted after with_mode cache reset, background color re-emitted, attribute cache reset, and reset_render_state clears all cached style state.
    - BUG-007: 6 tests in `spec/termisu/version_spec.cr` — verifies VERSION is non-empty string, VERSION_MAJOR/MINOR/PATCH are integers >= 0, VERSION matches MAJOR.MINOR.PATCH format with component consistency, and VERSION_STATE is nil or non-empty string.

- [x] **Add regression specs for BUG-004 (ModeChange#changed?) and BUG-012 (Unicode width).** Write two focused specs:
  - BUG-004 in `spec/termisu/event/mode_change_spec.cr`: Verify that `ModeChange.new(mode: Mode::Echo, previous_mode: nil).changed?` returns `false` (first change is not a change). Verify that `ModeChange.new(mode: Mode::Echo, previous_mode: Mode::None).changed?` returns `true`. Verify that same-mode transitions return `false`.
  - BUG-012 in `spec/termisu/unicode_width_spec.cr`: Verify that the previously over-classified neutral codepoints now return width 1:
    - `UnicodeWidth.codepoint_width(0x1F780)` should be `1` (not 2)
    - `UnicodeWidth.codepoint_width(0x1F7D9)` should be `1` (not 2)
    - Also verify that known emoji codepoints that should remain wide still return 2 (e.g., common emoji in the 0x1F900+ range)
  - **Done:** Added/verified regression tests for both bugs:
    - BUG-004: 3 new tests in `spec/termisu/event/mode_change_spec.cr` under "#changed? (BUG-004 regression)" — verifies nil previous_mode returns false with Mode::Echo, Echo vs None returns true, and same-mode Echo-to-Echo returns false. All 18 examples pass.
    - BUG-012: Already had comprehensive regression tests (added in prior phase) in `spec/termisu/unicode_width_spec.cr` — "neutral non-emoji supplementary codepoints (BUG-012)" verifies 0x1F780 and 0x1F7D9 return width 1, and "emoji within previously overbroad supplementary range" verifies 0x1F900+ emoji still return width 2. All 49 examples pass.

- [x] **Run the full test suite and fix any failures.** Execute:
  - `bin/hace format` — fix any formatting issues
  - `bin/hace ameba` — fix any linting issues
  - `bin/hace spec` — run all specs (should pass 1077+ examples, 0 failures)
  - If any new spec fails, investigate and fix the underlying issue in the relevant phase's code
  - Confirm total test count is higher than the baseline 1077 (new regression tests added)
  - **Done:** All three quality gates pass clean. `bin/hace format` — no changes needed. `bin/hace ameba` — 116 files inspected, 0 failures. `bin/hace spec` — 1130 examples, 0 failures, 0 errors, 0 pending. Test count of 1130 exceeds baseline of 1077 by 53 tests (regression tests from Phases 1-4).

- [x] **Update codex-bug-findings.md to mark all 10 bugs as closed.** Move BUG-001 through BUG-007 and BUG-010 through BUG-012 from the "Execution Queue" section to the "Closed / Archived" section. For each, add:
  - `Status: Closed (fixed in code)`
  - A brief `Validation:` note describing how the fix was verified
  - Update the "Total Open Tasks" count at the bottom to 0
  - **Done:** Moved all 10 bugs (BUG-001 through BUG-007, BUG-010 through BUG-012) from Execution Queue to Closed / Archived. Each entry now has `Status: Closed (fixed in code)` and a `Validation:` note summarizing the fix and regression test coverage. Execution Queue section now reads "No open bugs remaining." Total Open Tasks updated to **0**. Snapshot updated to current counts: 1130 examples, 0 failures; 116 inspected, 0 lint failures.
