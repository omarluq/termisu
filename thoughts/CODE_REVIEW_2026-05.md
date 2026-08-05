# Termisu Crystal Codebase Review — 2026-05-30

Full review of all 71 `src/**/*.cr` files (~10,628 lines) via 8 parallel subsystem
reviewers, each reading every file in its area. Headline findings independently
re-verified by direct read + `crystal eval`. Severities reflect verification, not
the raw reviewer claim. Cross-referenced against `KNOWN_ISSUES.md`; **NEW** marks
findings not in that backlog.

Verification legend: ✅ verified by me · ☑ reviewer ran a repro · ◻ plausible, unverified.

---

## CRITICAL

### C1 — No UTF-8 multibyte decode; all non-ASCII text input is mangled ✅ NEW
`src/termisu/input/parser.cr:160,187,200` (also 154). The byte→char path is
`Key.from_char(byte.chr)` on a single `UInt8`. Verified: `0xC3_u8.chr` → U+00C3
(Latin-1), `0xE9_u8.chr` → 233 — `UInt8#chr` is a raw Latin-1 map, never a UTF-8
decode. Typing `é` (UTF-8 `C3 A9`) emits two bogus `Key::Unknown` events; every
BMP/emoji char is shredded into 2–4 garbage events. No lead-byte detection, no
continuation-byte read loop. For a library that advertises Unicode/wide-char
*rendering*, raw text *entry* of any non-ASCII char is broken. Fix: in the `else`
branch detect a UTF-8 lead byte (0xC0/0xE0/0xF0 masks), read 1–3 continuation
bytes through the reader (same split-read timeout strategy as C2), assemble +
validate the codepoint, emit one key event. Interacts with C2 (continuation
bytes can straddle `read()` boundaries) — solve both with one
`next_byte_within(timeout)` primitive.

---

## HIGH

### H1 — `Termisu#close` is not exception-safe: a raise skips terminal restoration ✅ (rel. TERMISU-001)
`src/termisu.cr:84-96`. The four teardown steps (`@event_loop.stop`,
`@reader.close`, `@terminal.close`, `Logging.*`) run as bare sequential
statements with no `ensure`. If `@event_loop.stop` (joins fibers, sends on
channels) or `@reader.close` raises, `@terminal.close` never runs — user is left
in raw mode + alternate screen + mouse tracking on = unusable shell. Terminal
restoration is the one hard guarantee a TUI library must keep. Same pattern in
`terminal.cr` close (the cosmetic `disable_mouse`/`exit_alternate_screen` writes
flush to the TTY first; if that write fails on SIGHUP/disconnect, `disable_raw_mode`
+ `@backend.close` never run → fd leak + raw termios). Fix: put termios restore +
fd close in `ensure` so they always run.

### H2 — Split escape/mouse sequences silently corrupt input ✅ NEW (broader than TERMISU-013)
`src/termisu/input/parser.cr:199,363,388,433-435` + `reader.cr:284-288`.
Only the top-level ESC disambiguation calls `wait_for_data` (parser.cr:168). Once
inside a CSI/SS3/SGR-mouse/normal-mouse body, continuation bytes are fetched with
bare `@reader.read_byte`, no wait. `fill_buffer` treats `EAGAIN` as "no data" →
`read_byte` returns `nil`. If a sequence splits across two `read()`s (9600 baud,
SSH, paste under load — the 128-byte buffer makes whole-sequence delivery *likely*
but never *guaranteed*), `parse_csi_sequence` returns `Key::Unknown` and the tail
(`2 0 0 ~`) is reparsed as 4 stray keystrokes; `parse_normal_mouse` loses sync.
Timing-dependent, intermittent. Fix: route every mid-sequence fetch through a
helper that, on `nil`, does `wait_for_data(ESCAPE_TIMEOUT_MS)` and retries once.

### H3 — FFI use-after-free: handle lock released before the call runs ✅ NEW (supersedes TERMISU-001)
`src/termisu/ffi/core.cr:203-208` + `registry.cr:7,16,20`. `with_context` does
`context = Registry.fetch(handle)` (acquires lock, returns context, **releases
lock**) then `yield context` lock-free. A concurrent `termisu_destroy(h)` on
another thread `context.close`s (tears down reader/terminal/TTY fds) +
`Registry.delete`s while the first thread is mid-`render`/`set_cell` → write to a
closed TTY / freed state. `poll_event` is worst: it blocks in
`@event_loop.output.receive` holding the context, and a `destroy` stops the loop
underneath it. The thread-local error state implies multi-thread use is expected,
but no "one thread per handle" contract is documented/enforced. Fix: hold a
per-context lock (or refcount "in use" flag) for the call duration and make
`destroy` no-op/fail while a call is in flight — or document+enforce
single-thread-per-handle.

### H4 — FFI `Context#close` rolls back `@closed` on exception → raw-fd double-close ✅ (TERMISU-001, deeper)
`src/termisu/ffi/context.cr:11-20` → `tty.cr:62-65`. `close` does
`compare_and_set(false,true)` then on exception rolls `@closed` back to `false`.
`::Termisu#close` is not idempotent, so a retried `destroy` re-runs the whole
teardown. On Linux `TTY#close_input_fd` does `LibC.close(@in.as(Int32))` with no
guard; `@in` is a raw fd → second teardown re-issues `close(2)` on that integer =
classic fd-reuse double-close (closes whatever fd got that number meanwhile). Fix:
make close idempotent (set `@in = -1` after close, skip if `< 0`); treat close as
terminal even if it raises.

### H5 — Terminfo string-offset arithmetic overflows Int16 → unhandled crash on crafted file ☑ NEW
`src/termisu/terminfo/parser.cr:254` (also 177, 221-234). `read_string_at` does
`string_pos = (table_start + offset).to_i` — both operands are Int16, added *as
Int16* before widening. Reviewer confirmed via `crystal eval` that Crystal raises
`OverflowError` (does not wrap). Terminfo files are UNTRUSTED external input
(`$TERMINFO`, `~/.terminfo`). A positive `offset` near Int16::MAX overflows before
the `>= @data.size` bounds check can run; `OverflowError` escapes `parse?` (which
rescues only `ParseError`). DoS on attacker-placed terminfo. Fix: widen first —
`table_start.to_i32 + offset.to_i32` — then the existing bounds check catches it
and raises proper `ParseError`. (Note: TERMISU-014's "OOB read past buffer" is
actually *false* — `IO::Memory#read_byte` returns nil at EOF; the real
memory-safety severity belongs here at :254, and TERMISU-014's NUL-scan is only a
LOW "silent truncation".)

### H6 — Pollers process only `events[0]`, dropping the rest of each ready batch ✅ NEW
`src/termisu/event/poller/linux.cr:196` + `kqueue.cr:197`. Both declare a
16-slot event array, request up to 16 from `epoll_wait`/`kevent`, then handle
`events[0]` and `return`. When `n > 1` (e.g. input fd + resize self-pipe both
ready in one wakeup), the others are dropped that cycle. Level-triggered epoll
re-reports next `wait` (latency/fairness bug); kqueue edge cases can genuinely
drop. Defeats the point of the batch and starves fds under load. Fix: iterate
`events[0...n]`, buffer extras in a small queue served before the next syscall.

### H7 — Event-loop shutdown closes the channel under possibly-blocked producers; no fiber joins ✅ NEW (broader than TERMISU-009)
`src/termisu/event/loop.cr:143-162`. `stop` flips `@running=false`, sleeps 10ms,
yields once, then `@output.close` — never joins any source fiber. `Source::Input`
uses a **blocking** `output.send` (input.cr:111); a stalled consumer parks it
inside `send`, which the flag-flip can't wake, so close races a blocked producer
(rescued, so contained today, but structurally fragile). `Source::Resize`
(resize.cr:236) also blocking-sends and **has no `rescue Channel::ClosedError`** —
an unhandled fiber exception prints to STDERR (the render channel). Fix: make every
source's blocking point interruptible (the `send_nonblocking`+drop-counter the two
timers already use) and have `stop` join each source fiber before `@output.close`.

### H8 — `Color.rgb(Int,…)` raises raw `OverflowError` instead of `ArgumentError`; no `validate_rgb` ✅ NEW
`src/termisu/color.cr:84-86`. `r.to_u8`/`g.to_u8`/`b.to_u8` with no validation;
`300.to_u8` and `(-1).to_u8` both raise `OverflowError`, not the library's
`ArgumentError`. Every other public constructor (`ansi8`/`ansi256`/`grayscale`/
`from_hex`) validates. `from_hex` is safe (hex bytes ≤255). Fix: add
`Validator.validate_rgb` (0..255) called before `to_u8`. (FFI path is safe — ABI
already passes UInt8.)

---

## MEDIUM (selected; full list in per-subsystem notes)

- **M1 — `RenderState#reset` then `apply_style(attr: None)` emits no `\e[0m`** ✅ (TERMISU-004).
  `render_state.cr:73-75,51-54`. `default_state` returns `Attribute::None` (not a
  `nil` sentinel like fg/bg), so after `reset`/`sync`/`suspend{vim}` a terminal left
  bold/italic bleeds into the first cell. Fix: `@attr : Attribute?`, nil post-reset.
- **M2 — VTIME written to wrong `c_cc` index on Linux** ✅ NEW (reviewer said CRITICAL+both;
  reality: only VTIME). `termios.cr:24-25,112`. Stdlib defines `LibC::VMIN`=6
  (correct) but **not** `LibC::VTIME`, so the fallback `VTIME = 17` (a BSD value) is
  used; line 112 writes to `c_cc[17]` (reserved slot) instead of `c_cc[5]`. Masked
  because inherited VTIME is usually 0, so raw-mode VMIN=1/VTIME=0 happens to hold.
  Fix: define per-platform (Linux VTIME=5, BSD/Darwin 17).
- **M3 — `rgb_to_ansi256` maps pure black/white to near-black/near-white grays** ☑ NEW.
  `color/conversions.cr:42-54,99-105`. All `r==g==b` route to the 24-step gray ramp
  (never compares cube distance); `(0,0,0)`→232 (RGB 8) not cube 16; `(255,255,255)`→
  255 (RGB ~238) not cube 231. Plus grayscale index truncates (floor), biasing dark.
  Fix: compute cube + gray candidates, pick min Euclidean distance; `round` not floor.
- **M4 — `with_mode` restoration emits an inverted `ModeChange` and can re-enter alt screen
  after a partial failure** ✅ NEW. `terminal.cr:341-374` + `termisu.cr:598-604`. The
  facade ensure reads `restored_mode` *after* the backend ensure already restored, so
  the event reports `previous_mode: <block's mode>` (inverted). Fix: guard restoration
  on a "did we switch" flag; fix event arg order.
- **M5 — FFI bad codepoint/color routed to generic `Status::Error` via throw-and-catch** ✅
  (TERMISU-010, refined). `ffi/core.cr:91-103`, `conversions.cr:39`. No UB (validated
  + caught), but C callers can't distinguish "bad input" from "internal panic", and a
  hot loop pays exception-unwind per cell. Fix: cheap pre-validation returning
  `InvalidArgument`/`Rejected`.
- **M6 — SystemTimer `stop` closes poller fds under a blocked `poller.wait`** ◻ NEW.
  `event/source/system_timer.cr:103-114`. Use-after-close on raw fds guarded only by a
  hand-rolled run-token race. Fix: self-pipe/eventfd wake instead of close-under.
- **M7 — `kqueue.cr:201,240` `event.data.to_u64` raises on negative signed data**;
  **`kqueue.cr:195` blocking wait returns nil on spurious `n==0`** (treated as shutdown);
  **`linux.cr:82-91` `unregister_fd` tolerates ENOENT but not EBADF** → raises during
  teardown if fd closed first. ✅ NEW (poller layer).
- **M8 — Terminfo `%c` (`output.cr:7-8`) raises/ emits invalid UTF-8** on out-of-Int32 or
  >0x10FFFF values from untrusted string caps. ☑ NEW. Fix: clamp to byte/codepoint.
- **M9 — `$TERM` flows unsanitized into `File.join`** (`terminfo/database.cr:78,85`) — path
  traversal, LOW real risk (user's own env, read-only, magic-checked). = TERMISU-035.

---

## Confirmed-from-KNOWN_ISSUES (still valid, re-verified)

- **TERMISU-002 / 011 — per-cell + per-batch String allocation in the render hot path** ✅.
  `buffer.cr:473` `@batch_buffer.to_s` (one String/style-run), `cell.cr:101`
  `each_grapheme.first.to_s`, `buffer.cr:103` `ch.to_s`. A full-screen ASCII redraw
  allocates ~2–3 Strings/changed cell/frame. The stated "zero-allocation steady state"
  is not met. Fix: ASCII fast-path in `grapheme=`/`UnicodeWidth.grapheme_width`; a
  renderer `write` that consumes the `IO::Memory` directly.
- **TERMISU-008 / 017 — facade + terminal.cr god-objects** ✅ (facade also does mode
  orchestration: `pause/resume_input_processing` reaches into source/reader/loop).
- **TERMISU-003 / 007 / 020 — double SGR cache (RenderState + Terminal `@cached_*`),
  18-method Renderer, 2×8 `includes?` per attr change** ✅. Best fixed as one bundle.
- **TERMISU-015 / 022 — `Color.ansi8(-1)` accepted; `Color::Mode` lacks `Default` (FFI
  ColorMode has it)** ✅. Root cause of 3 findings; promote `Default` to a real Mode.
- **TERMISU-019 — `split(';')` per special key** ✅, and **mouse motion is the real hot
  path** (per-event in `parse_sgr_params_to_event`), undersold by the ticket.
- **TERMISU-024 / 025 — Cell fuses display + grid-occupancy; NUL-as-empty contract** ✅.

---

## New HIGH not in KNOWN_ISSUES — render-batch continuation edge ◻
`buffer.cr:457-471`. If a wide leading cell is unchanged (`==`) but its continuation
partner is inconsistent, the batch break-then-reenter can land `render_row_batch` on a
continuation cell as `first_cell`, emitting a stray `move_cursor` with no write
(`chars.empty?` guard). Invariants are assumed but never asserted on the render path.
Reviewer flagged "verify with a test that flips a single continuation cell's `==`
state" — not independently confirmed; treat as a robustness/assert-the-invariant item.

---

## Architectural themes (recurring across subsystems)

1. **Shutdown is timing-based, not signal-based.** Loop stop, SystemTimer stop, and
   close paths all flip a flag + sleep + hope, instead of *waking* blocked producers
   and *joining* fibers. Root of H1, H4, H7, M6. One design move (interruptible blocking
   points + bounded joins) closes the whole family.
2. **Exception-as-validation at the FFI + Color boundary.** Bad input throws-and-catches
   (H3-adjacent, H8, M5). A thin pre-validation layer returning typed statuses is faster
   and more diagnosable; leave `Guards` to catch true bugs.
3. **Int16-everywhere terminfo offset math** (H5) — the validator already widened to Int32
   at parser.cr:162; the rest should follow rather than rely on `MAX_*` caps staying < 32767.
4. **The `-1` default-color sentinel** spawns 3 findings (H8-adjacent, M9, FFI asymmetry).
   First-class `Color::DEFAULT` / `Mode::Default` collapses them.
5. **`Source` abstract class copy-pastes Atomic+CAS+spawn+rescue** 4× — and the one that
   diverged (resize, no rescue) is exactly H7's bug. Template-method base would make the
   rescue + future `join` structural.

---

## Suggested fix order (impact × effort)

1. **C1** UTF-8 decode + **H2** split-sequence wait — one shared `next_byte_within` primitive. (correctness of all input)
2. **H1/H4** idempotent + ensure-wrapped close (raw-fd guard) — the library's core guarantee.
3. **H5** terminfo Int16→Int32 offsets — untrusted-input DoS, ~3 line fix.
4. **H3** FFI handle lifetime (per-context lock / in-use flag) — C-ABI memory safety.
5. **H7/M6** event-loop join + interruptible sends — shutdown race family.
6. **H6** poller drain-all-events.
7. **M1** RenderState attr sentinel, **H8/M3** color validation + nearest-neighbor.
8. Perf bundle: TERMISU-002/011/003/007/020 (allocation + double SGR cache).
