# Codex Bug Findings

Execution backlog for confirmed and high-confidence defects in `termisu`.

## Snapshot (2026-02-25)

Validation run via `bin/hace`:
- `bin/hace spec` -> pass (`1130 examples, 0 failures`)
- `bin/hace ameba` -> pass (`116 inspected, 0 failures`)

This file is cleaned for execution planning:
- Open, actionable bugs are in **Execution Queue**.
- Already-fixed items are moved to **Closed / Archived**.

## Execution Queue

No open bugs remaining.

## Closed / Archived

### BUG-001: Sync Update Mode Can Be Left Open On Render Exceptions

Status: Closed (fixed in code)

Location:
- `src/termisu/terminal.cr`

Validation:
- `render` and `sync` methods now wrap buffer operations in `ensure` blocks so `end_sync_update` always executes after `begin_sync_update`.
- 4 regression tests in `spec/termisu/terminal/sync_update_spec.cr` verify ESU emitted after render/sync exceptions, flush occurs after exception, and BSU/ESU counts are paired.

---

### BUG-002: SIGWINCH Trap Uses Blocking Channel Send

Status: Closed (fixed in code)

Location:
- `src/termisu/event/source/resize.cr`

Validation:
- Signal handler replaced with true non-blocking signaling pattern to prevent blocking under resize bursts.
- 3 regression tests in `spec/termisu/event/source/resize_spec.cr` verify events delivered via polling without blocking, no deadlock with minimal channel capacity, and continued delivery after channel drain.

---

### BUG-003: `register_fd` Contract Inconsistent Across Poller Backends

Status: Closed (fixed in code)

Location:
- `src/termisu/event/poller/poll.cr`
- `src/termisu/event/poller/linux.cr`
- `src/termisu/event/poller/kqueue.cr`

Validation:
- Linux backend now uses `EPOLL_CTL_ADD` with fallback to `EPOLL_CTL_MOD` on `EEXIST`.
- Kqueue backend properly replaces previous filters.
- Contract standardized to "register updates existing registration" across all backends.

---

### BUG-004: `ModeChange#changed?` Contradicts Its Own Documentation

Status: Closed (fixed in code)

Location:
- `src/termisu/event/mode_change.cr`

Validation:
- Code aligned with documentation: first change (`previous_mode == nil`) now returns `false`.
- 3 regression tests in `spec/termisu/event/mode_change_spec.cr` verify nil previous_mode returns false, different modes return true, and same-mode transitions return false.

---

### BUG-005: `Terminal::Backend#read` Does Not Retry `EINTR`

Status: Closed (fixed in code)

Location:
- `src/termisu/terminal/backend.cr`

Validation:
- Added retry-on-`EINTR` loop consistent with `Reader#fill_buffer` behavior.
- 5 regression tests in `spec/termisu/terminal/backend_spec.cr` exercise EINTR retry happy path through Reader with pipe I/O, EOF handling, multi-byte reads, peek, and retry limit constant verification.

---

### BUG-006: Terminal Render Cache Can Be Stale After `with_mode(..., preserve_screen: true)`

Status: Closed (fixed in code)

Location:
- `src/termisu/terminal.cr`

Validation:
- Terminal render cache (`@cached_fg/@cached_bg/@cached_attr`) now reset in restore path for non-raw mode transitions including `preserve_screen: true`.
- 4 regression tests in `spec/termisu/terminal_spec.cr` verify foreground/background color re-emitted, attribute cache reset, and `reset_render_state` clears all cached style state after mode switch.

---

### BUG-007: Compile-Time Version Macro Hard-Fails Without `shards` In PATH

Status: Closed (fixed in code)

Location:
- `src/termisu/version.cr`

Validation:
- Version constants now parse `shard.yml` directly as fallback when `shards` is unavailable.
- 6 regression tests in `spec/termisu/version_spec.cr` verify VERSION is non-empty, VERSION_MAJOR/MINOR/PATCH are integers >= 0, VERSION matches component format, and VERSION_STATE is nil or non-empty string.

---

### BUG-008: Wide-over-wide overwrite orphan continuation

Status: Closed (fixed in code)

Location:
- `src/termisu/buffer.cr`

Validation:
- Existing specs pass and overlap-clearing logic now clears stale continuation ownership.

---

### BUG-009: Diff batching could start at continuation column

Status: Closed (fixed in code)

Location:
- `src/termisu/buffer.cr`

Validation:
- Continuation cells are skipped before style-break decisions in diff batching.

---

### BUG-010: `Reader` Crashes For File Descriptors >= `FD_SETSIZE`

Status: Closed (fixed in code)

Location:
- `src/termisu/reader.cr`

Validation:
- Guard added for fd >= `FD_SETSIZE` (1024) that falls back to poll-based readiness check instead of crashing with `IndexError`.
- 5 regression tests in `spec/termisu/reader_spec.cr` verify FD_SETSIZE=1024, fd=1024 and fd=2048 raise IOError (not IndexError) via poll fallback, normal pipe fds use select path, and wait_for_data with high fd.

---

### BUG-011: Poll Fallback Ignores User Timeout When Timers Exist

Status: Closed (fixed in code)

Location:
- `src/termisu/event/poller/poll.cr`

Validation:
- Deadline tracking added based on caller timeout; returns `nil` once elapsed regardless of timer presence.
- 3 regression tests in `spec/termisu/event/poller_spec.cr` verify wait(20ms) returns nil within ~50ms despite 200ms timer, wait(10ms) returns quickly with multiple long timers, and timer fires before user timeout when timer is shorter.

---

### BUG-012: Unicode Supplementary Width Range Overclassifies Neutral/Non-Emoji Codepoints As Wide

Status: Closed (fixed in code)

Location:
- `src/termisu/unicode_width.cr`

Validation:
- Broad `1F780..1FAFF` width rule replaced with explicit wide/emoji ranges derived from Unicode data.
- Regression tests in `spec/termisu/unicode_width_spec.cr` verify neutral non-emoji codepoints (U+1F780, U+1F7D9) return width 1, and emoji codepoints (0x1F900+ range) still return width 2.

## Total Open Tasks

Open bugs ready for execution: **0**.
