# Phase 03: Signal and Mode Robustness

This phase fixes the SIGWINCH blocking-send hazard and the stale render cache after mode switches — two medium-severity bugs that cause subtle corruption under real-world usage. After this phase, resize bursts can't block the signal handler, and switching terminal modes with preserved screen won't leave stale color/attribute cache entries that skip needed escape sequences.

## Tasks

- [x] **BUG-002: Replace blocking channel send in SIGWINCH trap with non-blocking signaling.** In `src/termisu/event/source/resize.cr` at line ~172, the signal handler does `signal_channel.try &.send(nil) rescue nil`. Although it uses `rescue nil` for error suppression, `Channel#send` blocks when the channel buffer is full, which is unsafe inside a signal handler. Fix by using a truly non-blocking approach:
  - Option A (preferred): Use `Atomic(Bool)` as a flag instead of a channel send in the trap. Set `@signal_received.set(true)` in the trap. In the polling fiber (`run_loop`), periodically check `@signal_received.swap(false)` and process the resize when it's true.
  - Option B: Use `select` with an `else` clause in the trap — but Crystal signal traps have restrictions on what fiber/GC operations are allowed.
  - Option C: Use a pipe (`IO.pipe`) and write a single byte — pipe writes of ≤ PIPE_BUF bytes are atomic and non-blocking when the buffer isn't full.
  - Whichever approach you choose, ensure the existing resize detection behavior is preserved: resize events still fire promptly, debouncing still works, and the `run_loop` method continues to function correctly.
  - Review `run_loop` to understand how it consumes the signal channel currently and adapt accordingly.
  - **DONE (Option A):** Replaced `@signal_channel` with `@signal_received : Atomic(Bool)`. Signal handler now calls `signal_received.set(true)` (always non-blocking). `run_loop` uses `sleep(@poll_interval)` then `@signal_received.swap(false)` instead of `select` on a channel. All 1080 specs pass.

- [x] **BUG-006: Reset terminal render cache after with_mode with preserve_screen.** In `src/termisu/terminal.cr` at line ~392, the `with_mode` method's `ensure` block (line ~408) invalidates the buffer via `invalidate_buffer` but never resets the cached style state (`@cached_fg`, `@cached_bg`, `@cached_attr`). When `preserve_screen: true`, the same screen is used, but external programs may have changed terminal styling. On return, the cached values make the renderer think it doesn't need to re-emit style sequences, causing visual corruption. Fix by:
  - In the `ensure` block of `with_mode`, after `invalidate_buffer`, also reset the render cache: set `@cached_fg = nil`, `@cached_bg = nil`, `@cached_attr = Attribute::None`
  - This ensures the next render will re-emit all style escape sequences from scratch
  - The reset should happen for ALL non-raw mode transitions, not just `preserve_screen: true`, since any mode block could have external writes that invalidate our assumptions
  - Verify that `reset_attributes` method exists and consider calling it (but note it writes an escape sequence too — just resetting the instance variables without writing may be more appropriate here)
  - **DONE:** Already fixed in commit 79f3347. The `ensure` block at line ~420 calls `reset_render_state` which clears `@cached_fg = nil`, `@cached_bg = nil`, `@cached_attr = Attribute::None`, and `@cached_cursor_visible = nil`. This is unconditional (applies to ALL mode transitions, not just `preserve_screen: true`). Using `reset_render_state` instead of `reset_attributes` is correct because it only clears the cached instance variables without writing an escape sequence to the terminal.

- [x] **Run `bin/hace spec` and `bin/hace ameba` to verify all changes pass.** Pay attention to any resize-related or mode-change-related specs to ensure no regressions.
  - **DONE:** All 1080 specs pass (0 failures, 0 errors, 0 pending). Ameba: 113 files inspected, 0 failures. No regressions in resize or mode-change specs.
