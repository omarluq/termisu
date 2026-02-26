# Phase 01: Critical Safety Fixes

This phase fixes the two high-severity bugs and the most impactful medium bugs — all related to terminal safety and robustness. These are the "leave your terminal broken" and "silently ignore your timeout" class of defects. By the end of this phase, `render`/`sync` are exception-safe, Backend reads survive signal interruption, the poll timeout contract is honored, and the version macro won't blow up in containers. Run `bin/hace spec` at the end to confirm zero regressions.

## Tasks

- [x] **BUG-001: Wrap render/sync in ensure for sync update mode safety.** In `src/termisu/terminal.cr`, the `render` method (line ~546) and `sync` method (line ~558) call `begin_sync_update` then the buffer operation then `end_sync_update`. If the buffer operation raises, `end_sync_update` is never called and DEC synchronized update mode (BSU) is left open, freezing the terminal. Fix both methods to use `begin`/`ensure` so `end_sync_update` always runs after `begin_sync_update`. The pattern is:
  - `render`: wrap `@buffer.render_to(self, auto_flush: !@sync_updates)` in begin/ensure with `end_sync_update` in the ensure block
  - `sync`: wrap `@buffer.sync_to(self, auto_flush: !@sync_updates)` in begin/ensure with `end_sync_update` in the ensure block
  - Keep `begin_sync_update` before the begin block (or at the start of it)

- [x] **BUG-005: Add EINTR retry loop to Backend#read.** In `src/termisu/terminal/backend.cr` at line ~79, the `read` method does a single `LibC.read` and raises on any negative return. This fails spuriously when a signal (like SIGWINCH) interrupts the read. Add a retry loop that checks `Errno.value == Errno::EINTR` and retries, consistent with the existing pattern used in `Reader#fill_buffer` (`src/termisu/reader.cr`). The loop should:
  - Call `LibC.read(@infd, buffer, buffer.size)`
  - If result >= 0, return `result.to_i32`
  - If result < 0 and errno is EINTR, retry (`next`)
  - If result < 0 and errno is anything else, raise `IO::Error.from_errno("read failed")`

- [x] **BUG-011: Fix poll fallback ignoring user timeout when timers exist.** In `src/termisu/event/poller/poll.cr`, the `wait_internal` method (line ~153) loops calling `poll()` but never tracks elapsed wall-clock time against the caller's timeout. When timers exist and `result == 0` (line ~178), it only returns nil if `@timers.empty?`, so it keeps looping until a timer fires — ignoring the user's requested timeout entirely. Fix by:
  - Recording a deadline at method entry: `deadline = user_timeout ? Time.monotonic + user_timeout : nil`
  - After each `poll()` call, before the timer/fd checks, check if the deadline has passed: `if deadline && Time.monotonic >= deadline` then `return nil`
  - This ensures `wait(20.milliseconds)` returns nil in ~20ms even when timers are registered for longer intervals
  - Also update `calculate_timeout` to factor in the remaining time to deadline so poll doesn't sleep past it

- [x] **BUG-007: Add fallback for version macro when shards is unavailable.** In `src/termisu/version.cr`, the compile-time macros call `shards version` directly (lines 8 and 12). If `shards` is not in PATH, the build hard-fails. Fix by parsing `shard.yml` directly at compile time instead. The approach:
  - Use `{{ read_file("#{__DIR__}/../shard.yml") }}` or `{{ run("cat", "shard.yml") }}` approach — but simplest is to read the file and parse the version line with macro string operations
  - Alternatively: use a rescue/fallback macro pattern — try `shards version` first, fall back to parsing `shard.yml`, and ultimately default to `"0.0.0-unknown"` if both fail
  - The current shard.yml has `version: 0.3.1` on line 2, so parsing is straightforward
  - Keep VERSION_MAJOR, VERSION_MINOR, VERSION_PATCH, and VERSION_STATE constants working correctly

- [x] **BUG-010: Guard Reader against fd >= FD_SETSIZE (1024).** In `src/termisu/reader.cr` at line ~123, `check_fd_readable` computes `word_index = @fd // 64` and uses it to index into `fd_set.fds_bits` without bounds checking. For fd >= 1024, this causes an `IndexError` crash. Fix by:
  - At the top of `check_fd_readable` (or wherever `fd_set` is used with the raw fd), add a guard: `if @fd >= 1024` then fall back to `LibC.poll` for readiness checking instead of `select`, OR raise a clear `Termisu::IOError` / `ArgumentError` with a message like `"File descriptor #{@fd} >= FD_SETSIZE (1024), not supported by select()"`
  - The preferred approach is falling back to poll: create a single `LibC::Pollfd` struct, set fd and POLLIN, call `LibC.poll` with the timeout, and return whether POLLIN is set in revents
  - This makes Reader robust for high-fd processes

- [x] **Run `bin/hace spec` and `bin/hace ameba` to verify all changes compile, pass linting, and pass the existing 1077 tests with zero regressions.** Fix any format or lint issues found. Run `bin/hace format` before ameba if needed.
