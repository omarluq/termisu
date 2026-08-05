# Known Issues — Termisu

**Last updated:** 2026-07-20 (TERMISU-039 added; previous revision 2026-04-23 post-review)
**Against version:** 0.4.5
**Source of findings:** Four-dimensional analysis pass run 2026-04-22, followed by per-ticket verification, followed by an **adversarial review pass** on 2026-04-23 (see [`KNOWN_ISSUES_REVIEW.md`](./KNOWN_ISSUES_REVIEW.md)).

After the review, **6 tickets were closed as invalid**, 7 severities reduced, 4 ticket descriptions refined. See each ticket's top-matter for its post-review status.

Each remaining ticket has been **verified by direct file read**. Line numbers are anchored to the current tree and should be stable until someone edits the file. Unverified claims are labeled explicitly.

---

## Legend

**Severity:**
- **CRITICAL** — Live bug or perf regression breaking documented guarantees. Fix before next release.
- **HIGH** — Structural defect or correctness hole with significant downstream cost.
- **MEDIUM** — Real concern, worth queuing for a focused sprint.
- **LOW** — Polish, cosmetics, or defense-in-depth. Opportunistic fixes only.

**Status:**
- `OPEN` — Not started.
- `VERIFIED` — I read the source and confirmed the claim holds as stated.
- `VERIFIED-MODIFIED` — I confirmed the issue but adjusted severity or scope after reading.
- `NEEDS-REPRO` — Claim is plausible from reading, but reproduction requires runtime instrumentation not yet gathered.

**Component tags:** `[rendering]` `[io]` `[events]` `[input]` `[terminfo]` `[ffi]` `[color]` `[support]`

---

## Index

| ID | Severity | Component | Title |
|---|---|---|---|
| [TERMISU-001](#termisu-001) | HIGH *(↓ from CRITICAL)* | ffi | `FFI::Context#close` rolls back `@closed` on exception, enabling double-cleanup |
| [TERMISU-002](#termisu-002) | CRITICAL | rendering | Char-based `set_cell` allocates a String per cell, breaking 60 FPS budget |
| [TERMISU-003](#termisu-003) | HIGH | rendering | Double SGR state between `RenderState` and `Terminal`'s `@cached_*` fields |
| [TERMISU-004](#termisu-004) | HIGH | rendering | `RenderState#reset` followed by `apply_style(attr: None, …)` fails to emit `reset_attributes` |
| [TERMISU-005](#termisu-005) | HIGH | rendering | `set_cell` keyword arg name inconsistency (`grapheme:` vs `ch:`) silently breaks callers |
| [TERMISU-006](#termisu-006) | MEDIUM *(↓ from HIGH; split)* | support / input | Exceptions silently swallowed in `Logging.setup`, `Logging.close`, `codepoint_to_key` |
| [TERMISU-007](#termisu-007) | HIGH | rendering | `Renderer` abstraction exposes 18 methods; every new attribute ripples across 4 files |
| [TERMISU-008](#termisu-008) | HIGH | facade | `Termisu::Termisu` facade at ~797 lines with ~60 public methods is becoming a god object |
| [TERMISU-009](#termisu-009) | HIGH | events | `Source::Input` uses blocking `send` — keystrokes lost under backpressure without signal |
| [TERMISU-010](#termisu-010) | MEDIUM *(↓ from HIGH)* | ffi | FFI accepts out-of-range coordinates and codepoints; defense-in-depth hygiene |
| [TERMISU-011](#termisu-011) | HIGH | rendering | `Cell` construction + `@batch_buffer.to_s` allocate in diff hot path |
| [TERMISU-012](#termisu-012) | ❌ **CLOSED** | ffi | ~~`FFI::Registry` generation counter~~ — rejected: UInt64 wrap = 584 B years |
| [TERMISU-013](#termisu-013) | LOW *(↓ from MEDIUM)* | input | Input parser has no CPU budget — malformed CSI spam (defense-in-depth only) |
| [TERMISU-014](#termisu-014) | MEDIUM | terminfo | Terminfo binary parser's null-terminated string scan lacks end-of-data guard |
| [TERMISU-015](#termisu-015) | MEDIUM | color | `Color.ansi8(-1)` is silently valid; docstring and validator disagree |
| [TERMISU-016](#termisu-016) | ❌ **CLOSED** | facade | ~~`set_cursor` precedence~~ — rejected: Crystal precedence is actually correct |
| [TERMISU-017](#termisu-017) | MEDIUM | rendering | `terminal.cr` at ~699 lines mixes SGR, modes, mouse, enhanced keyboard, title, sync updates |
| [TERMISU-018](#termisu-018) | ❌ **CLOSED** | events | ~~SHUTDOWN_TIMEOUT_MS name~~ — rejected: `100 ms / 10` is documented, intentional |
| [TERMISU-019](#termisu-019) | MEDIUM | input | CSI parser uses `params.split(';')` — allocates Array+Strings per special key |
| [TERMISU-020](#termisu-020) | MEDIUM | rendering | `apply_attribute_change` does 2×8 `includes?` checks per style change |
| [TERMISU-021](#termisu-021) | LOW *(↓ from MEDIUM)* | ffi | `ffi/core.cr` is a grab-bag file — 219 lines, manageable; split only if it grows |
| [TERMISU-022](#termisu-022) | MEDIUM | color / ffi | Crystal `Color::Mode` lacks `Default`; ABI `ColorMode` has it — asymmetric contract |
| [TERMISU-023](#termisu-023) | LOW *(↓ from MEDIUM)* | events | Backpressure "scatter" is intentional differentiated semantics, not debt |
| [TERMISU-024](#termisu-024) | MEDIUM | rendering | `Buffer#invalidate` relies on implicit "NUL is never a real cell" contract |
| [TERMISU-025](#termisu-025) | MEDIUM | rendering | `Cell` struct fuses display data with grid-occupancy (continuation) |
| [TERMISU-026](#termisu-026) | ❌ **CLOSED** | io | ~~Reader buffer 128 bytes~~ — rejected: documented default, llms.txt was wrong |
| [TERMISU-027](#termisu-027) | LOW *(↓ from MEDIUM)* | events | `Event::Source` invariants documented but unenforced (revisit if custom sources appear) |
| [TERMISU-028](#termisu-028) | LOW | terminfo | `Terminfo` pre-caches 12 capabilities at ctor; list is hardcoded |
| [TERMISU-029](#termisu-029) | ❌ **CLOSED** | ffi | ~~FFI always compiled~~ — rejected: Crystal `--release` DCE strips unused symbols |
| [TERMISU-030](#termisu-030) | LOW | io | `TIOCGWINSZ` magic numbers duplicated per-platform without shared source |
| [TERMISU-031](#termisu-031) | LOW | terminfo | `Terminfo#to_status_line_seq` hardcodes sequence; should fallback to `get_cap` |
| [TERMISU-032](#termisu-032) | LOW | rendering | `Terminal#title=` has non-idiomatic setter return pattern |
| [TERMISU-033](#termisu-033) | LOW | rendering | `Attribute::Italic` is a documented alias for `Cursive`; `.to_s` always reports `"Cursive"` |
| [TERMISU-034](#termisu-034) | LOW | rendering | Three `# ameba:disable Naming/AccessorMethodName` suppressions without justification |
| [TERMISU-035](#termisu-035) | LOW | terminfo | `$TERM` is used unvalidated in file path construction (defense-in-depth) |
| [TERMISU-036](#termisu-036) | ❌ **CLOSED** | io | ~~EINTR retry storm~~ — rejected: counter is per-call, not cumulative |
| [TERMISU-037](#termisu-037) | MEDIUM | io | `Reader#close` does not close the fd; ownership model undocumented |
| [TERMISU-038](#termisu-038) | LOW | io | No runtime verification of `LibC::Winsize` struct size |
| [TERMISU-039](#termisu-039) | HIGH | rendering | `apply_attribute_change` drops attributes retained across a batch reset (Bold+Underline → Bold loses bold) |

**Rollup after 2026-04-23 review (see [`KNOWN_ISSUES_REVIEW.md`](./KNOWN_ISSUES_REVIEW.md)):**

| Severity | Original (post-verification) | After review | Delta |
|---|---|---|---|
| CRITICAL | 2 | **1** | TERMISU-001 reduced to HIGH (Terminal#close is idempotent) |
| HIGH | 9 | **7** | TERMISU-006 and -010 reduced to MEDIUM |
| MEDIUM | 18 | **13** | -4 (TERMISU-012/-016/-018/-026/-036 closed; -013/-021/-023/-027 reduced to LOW; +2 from HIGH) |
| LOW | 9 | **11** | +2 from MEDIUM downgrades; -1 (TERMISU-029 closed) |
| ❌ CLOSED | 0 | **6** | TERMISU-012, -016, -018, -026, -029, -036 |
| **Total** | **38** | **38** | No tickets added or deleted — statuses changed |

**Closed tickets retained in this file as historical record.** Jump to any closed ticket to see the reason. Do not reopen without new evidence.

---

---

## CRITICAL

### <a id="termisu-001"></a>TERMISU-001 — `FFI::Context#close` rolls back `@closed` on exception, enabling double-cleanup

**Severity:** HIGH  *(reduced from CRITICAL on 2026-04-23 review)*  •  **Status:** VERIFIED  •  **Component:** `[ffi]`
**Files:** `src/termisu/ffi/context.cr:11-20`

> **REVIEW NOTE (2026-04-23):** Reduced from CRITICAL to HIGH. `Terminal#close`, `Backend#close`, and `TTY#close` are all idempotent (each checks a state flag before acting). Worst case of the CAS rollback is redundant work on a second close call, not EBADF or resource corruption. Fix is still correct; urgency is not "before next release."

#### Verified source

```crystal
# src/termisu/ffi/context.cr:11-20
def close : Nil
  return unless @closed.compare_and_set(false, true)

  begin
    @termisu.close
  rescue ex
    @closed.set(false)
    raise ex
  end
end
```

#### Description

The "closed" CAS flag is set *before* `@termisu.close` runs, which is correct for idempotency. The bug is the **rescue branch resets the flag to `false`**. If `@termisu.close` raises after partial cleanup (e.g. TTY was closed but `Backend#close` raised mid-way through alternate-screen exit, or termios restore failed), a second call to `Context#close` passes the CAS guard and re-enters `@termisu.close` on an *already partially destroyed* instance. Depending on where the first call failed, this can attempt to `close(2)` a freed fd (EBADF), `tcsetattr` on a closed fd, or double-free wrapped resources.

#### Impact

- **Resource corruption**: Partial state leaves FFI-managed `Termisu` instances in an undefined state, then the retry compounds the corruption.
- **Debuggability**: The caller sees the original exception on the first call, but the *actual* fault (the second call crashing harder) appears elsewhere in the log.
- **C ABI surface**: Exposed to every C caller; a `termisu_close` that raises is likely to be retried by defensive callers.

#### Proposed fix

Never roll `@closed` back. Once close is attempted, the context is tainted. Track failure state separately:

```crystal
class Termisu::FFI::Context
  getter termisu : ::Termisu

  @closed : Atomic(Bool)
  @close_failed : Atomic(Bool)

  def initialize(sync_updates : Bool)
    @closed = Atomic(Bool).new(false)
    @close_failed = Atomic(Bool).new(false)
    @termisu = ::Termisu.new(sync_updates: sync_updates)
  end

  def close : Nil
    return unless @closed.compare_and_set(false, true)

    begin
      @termisu.close
    rescue ex
      @close_failed.set(true)
      raise ex
    end
  end

  def closed? : Bool
    @closed.get
  end

  def close_failed? : Bool
    @close_failed.get
  end
end
```

At the FFI export boundary, `termisu_close` on a `close_failed?` context should return `Status::Error` with the original error string preserved in `ErrorState`.

#### Verification notes

Exact code reproduced above. The security reviewer's scenario ("TTY closes successfully but `@termisu.close` raises (e.g., during buffer cleanup)") is plausible: `::Termisu#close` orchestrates event-loop stop, reader close, terminal close, and log close; any of these can raise.

---

### <a id="termisu-002"></a>TERMISU-002 — Char-based `set_cell` allocates a String per cell, breaking 60 FPS budget

**Severity:** CRITICAL  •  **Status:** VERIFIED  •  **Component:** `[rendering]`
**Files:** `src/termisu/buffer.cr:95-104` + `src/termisu/cell.cr:92-108`

#### Verified source

```crystal
# src/termisu/buffer.cr:95-104
def set_cell(
  x : Int32,
  y : Int32,
  ch : Char,
  fg : Color = Color.white,
  bg : Color = Color.default,
  attr : Attribute = Attribute::None,
) : Bool
  set_cell(x, y, ch.to_s, fg, bg, attr)
end
```

```crystal
# src/termisu/cell.cr:92-108
def grapheme=(@grapheme)
  if @continuation
    @grapheme = ""
    @width = 0u8
  elsif grapheme.empty?
    @grapheme = " "
    @width = 1u8
  else
    # Extract first grapheme cluster to ensure single-grapheme invariant
    first = grapheme.each_grapheme.first.to_s
    if first.bytesize < grapheme.bytesize
      Termisu::Logs::Buffer.debug { "Cell: multi-grapheme input truncated (#{grapheme.grapheme_size} graphemes, kept first)" }
    end
    @grapheme = first
    @width = UnicodeWidth.grapheme_width(@grapheme)
  end
end
```

#### Description

Two hot-path allocations per `Char` set-cell, plus unconditional grapheme-cluster iteration and a width-table lookup even for ASCII:

1. `ch.to_s` (`buffer.cr:103`) allocates a one-char `String`.
2. `grapheme.each_grapheme.first.to_s` (`cell.cr:101`) allocates again after iterating the grapheme segmenter — unnecessary for single ASCII bytes.
3. `UnicodeWidth.grapheme_width(@grapheme)` runs binary search over 236 combining-mark ranges + CJK block checks even for ASCII printable (which is always width 1).

#### Impact

For a full 80×24 cell fill at 60 FPS:

| Operation | Count | Per-frame | Per-second |
|---|---|---|---|
| `ch.to_s` allocations | 1920 | 1920 Strings | 115,200 Strings/sec |
| `each_grapheme.first.to_s` | 1920 | 1920 Strings | 115,200 Strings/sec |
| Binary searches + block checks | 1920 | ~23K comparisons | ~1.4M/sec |

GC pressure alone can blow the 16 ms frame budget on typical 60 FPS targets. This directly undermines the library's "zero-allocation steady-state rendering" goal.

#### Proposed fix

1. **ASCII fast path in `Buffer#set_cell(Char)`** — avoid the String round-trip entirely:

   ```crystal
   def set_cell(x, y, ch : Char, fg = Color.white, bg = Color.default, attr = Attribute::None) : Bool
     return false if out_of_bounds?(x, y)
     return false if control_char?(ch)

     if ch.ascii? && ch.ord >= 32
       cell = Cell.new_ascii(ch, fg: fg, bg: bg, attr: attr)  # new constructor
       set_cell_internal(x, y, cell, 1_u8)
       return true
     end

     set_cell(x, y, ch.to_s, fg, bg, attr)  # fall back for non-ASCII Char
   end
   ```

2. **ASCII fast path in `Cell.grapheme=`** — skip grapheme iteration for byte-sized ASCII:

   ```crystal
   def grapheme=(@grapheme)
     # ... existing continuation and empty branches ...
     else
       if grapheme.bytesize == 1 && grapheme.unsafe_byte_at(0) < 0x80
         @grapheme = grapheme
         @width = 1_u8
       else
         first = grapheme.each_grapheme.first.to_s
         # ... existing slow path ...
       end
     end
   end
   ```

3. **ASCII fast path in `UnicodeWidth.grapheme_width`** — short-circuit before the binary search:

   ```crystal
   def self.grapheme_width(grapheme : String) : UInt8
     return 0_u8 if grapheme.empty?
     return 1_u8 if grapheme.bytesize == 1 && grapheme.unsafe_byte_at(0) < 0x80
     # ... existing slow path ...
   end
   ```

#### Verification notes

Direct source read confirms both file regions exactly as quoted. Allocation count is back-of-envelope but the qualitative claim (per-cell allocation during Char writes) is undeniable.

#### Benchmarks needed

Before landing the fix: add a benchmark in `bench/suites/buffer_suite.cr` that fills an 80×24 buffer with `Char` set_cells, measures allocations/sec and wall time. Target: zero allocations in the ASCII steady state after the fix.

---

## HIGH

### <a id="termisu-003"></a>TERMISU-003 — Double SGR state between `RenderState` and `Terminal`'s `@cached_*` fields

**Severity:** HIGH  •  **Status:** VERIFIED  •  **Component:** `[rendering]`
**Files:** `src/termisu/render_state.cr:20-108` + `src/termisu/terminal.cr:36-38, 129-167, 182-249`

#### Description

Two independent SGR optimizers exist in the render path. `RenderState` (used by `Buffer#render_to`) tracks `(fg, bg, attr)` and emits only deltas via the Renderer interface. Separately, `Terminal` keeps `@cached_fg`, `@cached_bg`, `@cached_attr` and short-circuits inside each SGR-emitting method (`foreground=`, `background=`, `enable_bold`, etc.) when the cached value matches. Both caches live on the same call path: Buffer → RenderState → Terminal's Renderer interface → Terminal's cached setter.

The existence of the second cache has forced scattered patches (`reset_render_state` calls in `enter_alternate_screen`, `exit_alternate_screen`, `clear_screen`, `reset_attributes`) to keep them in sync.

#### Impact

- **Drift risk.** Two sources of truth for "what SGR is the terminal in?" Any code path that mutates one cache without the other introduces incorrect emissions — the terminal ends up with attributes the renderer thinks it already cleared.
- **Extension friction.** Adding a new attribute (e.g., `DoubleUnderline`, `Overline`) means editing Renderer, RenderState's `apply_new_attributes`, Terminal's cached setter, and a mock.
- **Test unsoundness.** Mock renderers cannot assert RenderState's intent because Terminal's cache short-circuits first. Tests end up asserting on byte output, which is brittle.

#### Proposed direction

Collapse into a single authoritative cache. `RenderState` is already at the Buffer ↔ Renderer boundary — keep its role as *the* SGR optimizer. Terminal becomes a dumb byte writer for SGR; direct-API callers (non-Buffer code paths) that need idempotency get a small `StyledWriter` helper or go through a shared `RenderState`.

This ticket is a refactor, not a patch. It should be bundled with TERMISU-007 (Renderer interface narrowing) and TERMISU-011 (Cell allocation cleanup) because they share the same code surface.

#### Verification notes

Both files read directly. `render_state.cr` has the canonical tracking logic (verified in full above). `terminal.cr` has separate `@cached_fg/@cached_bg/@cached_attr` fields with short-circuits at the top of the SGR emitters — this was confirmed from llms.txt §8.3 but should be re-read before the fix to ensure the line refs are current.

---

### <a id="termisu-004"></a>TERMISU-004 — `RenderState#reset` treats post-reset state as known when it should be unknown

**Severity:** HIGH  •  **Status:** VERIFIED (framing rewritten 2026-04-23)  •  **Component:** `[rendering]`
**Files:** `src/termisu/render_state.cr:30-37, 42-71, 84-89`

> **REVIEW NOTE (2026-04-23):** Original framing was imprecise. When `@attr == None` and `apply_style(attr: None)` is called, there is genuinely nothing to emit — skipping `reset_attributes` is *correct* if RenderState's belief matches the terminal. The real bug is narrower: **`reset()` sets `@attr = None` as an assertion about terminal state that may not be true** (e.g., after `suspend { system("vim") }`, vim can leave bold/underline set). If the first `apply_style` after reset uses `attr: None`, the mismatch persists until something forces a reset. Same fix (`Attribute?` nil sentinel), clearer description.

#### Verified source

```crystal
# render_state.cr:30-37
def initialize
  @fg, @bg, @attr = default_state
end

def reset
  @fg, @bg, @attr = default_state
end

# render_state.cr:73-75
private def default_state : Tuple(Color?, Color?, Attribute)
  {nil, nil, Attribute::None}
end
```

#### Description

`default_state` assigns `Attribute::None` (not `nil`) as the "post-reset" attribute. The asymmetry with `fg`/`bg` (which use `nil` sentinels to mean "unknown") creates a subtle bug in `apply_style`:

```crystal
# render_state.cr:51-54
if attr != @attr
  apply_attribute_change(renderer, attr)
  changed = true
end
```

After `reset`, `@attr == Attribute::None`. On the first `apply_style` call with `attr: Attribute::None`:
- `attr != @attr` → `None != None` → `false`
- `apply_attribute_change` is **skipped**
- `reset_if_removing_attrs` (which would emit `\e[0m`) is never reached

If the terminal has leftover attributes from a previous program (e.g., user returned from `vim` that left the terminal bold), the first cell drawn after reset silently inherits them. Colors avoid this because their `nil` sentinel forces `!=` to succeed.

#### Impact

Visible rendering glitches after:
- `suspend { system("vim") }` (post-shell-out screen state uncertain)
- `clear_screen` (which calls `reset_render_state`)
- `exit_alternate_screen` / `enter_alternate_screen` transitions

The glitch is "first cell drawn after reset is bold/italic when it shouldn't be." Symptomatic users would describe it as "my UI randomly has extra attributes for a frame."

#### Proposed fix

Option A (recommended) — make `@attr` also use a `nil` sentinel:

```crystal
property attr : Attribute?

def reset
  @fg, @bg, @attr = nil, nil, nil
end

# In apply_style:
if @attr.nil? || attr != @attr
  apply_attribute_change(renderer, attr)
  changed = true
end
```

Option B — force `reset_attributes` emit on first `apply_style` after reset via a separate `@needs_full_reset : Bool` flag.

Option A is cleaner and matches the existing `fg`/`bg` pattern.

#### Verification notes

Full source read of `render_state.cr` confirms the exact bug mechanics. The `reset_if_removing_attrs` at line 85-89 computes `@attr & ~new_attr`, which is always `None` when `@attr == None`, so that branch never fires post-reset. This is the same conclusion the architecture reviewer reached, re-verified against the file.

---

### <a id="termisu-005"></a>TERMISU-005 — `set_cell` keyword arg name inconsistency (`grapheme:` vs `ch:`) silently breaks callers

**Severity:** HIGH  •  **Status:** VERIFIED  •  **Component:** `[rendering]`
**Files:** `src/termisu/buffer.cr:66-73, 95-104`

#### Verified source

```crystal
# buffer.cr:66-73 (String overload)
def set_cell(
  x : Int32,
  y : Int32,
  grapheme : String,      # <-- parameter is named "grapheme"
  fg : Color = Color.white,
  bg : Color = Color.default,
  attr : Attribute = Attribute::None,
) : Bool

# buffer.cr:95-104 (Char overload)
def set_cell(
  x : Int32,
  y : Int32,
  ch : Char,              # <-- parameter is named "ch"
  fg : Color = Color.white,
  bg : Color = Color.default,
  attr : Attribute = Attribute::None,
) : Bool
  set_cell(x, y, ch.to_s, fg, bg, attr)
end
```

#### Description

Two public `set_cell` overloads with mismatched positional-parameter names. Called with keyword args, they dispatch differently:

```crystal
buffer.set_cell(10, 5, grapheme: "A")  # OK — String overload
buffer.set_cell(10, 5, grapheme: 'A')  # COMPILE ERROR — Char value, String parameter
buffer.set_cell(10, 5, ch: 'A')        # OK — Char overload
buffer.set_cell(10, 5, ch: "A")        # COMPILE ERROR — String value, Char parameter
```

The docstring above both overloads documents the parameter as `grapheme`, but the Char version's actual parameter is `ch`. The documentation lies.

#### Impact

- **Surface-area inconsistency.** A user learning the API from docs cannot confidently use keyword args.
- **Silent IDE surprises.** Completion suggests `grapheme:` (from the docstring), runtime rejects.
- **Cheap to fix** — parameter renaming is non-breaking because Crystal keyword arg names are part of the signature but not the ABI.

#### Proposed fix

Rename the `Char` overload parameter to match:

```crystal
def set_cell(
  x : Int32,
  y : Int32,
  grapheme : Char,   # renamed from ch
  fg : Color = Color.white,
  bg : Color = Color.default,
  attr : Attribute = Attribute::None,
) : Bool
  set_cell(x, y, grapheme.to_s, fg, bg, attr)
end
```

(Or rename the String overload to `ch : String` — less conventional, less preferred.)

Cross-check callers in `spec/` and `examples/` to ensure none use the positional `ch:` keyword. None should, since the parameter is positional in practice.

#### Verification notes

Both overloads read directly. The docstring at `buffer.cr:52-65` refers to the parameter as "grapheme" for both, confirming the doc/code drift.

---

### <a id="termisu-006"></a>TERMISU-006 — Exceptions silently swallowed in `Logging.setup`, `Logging.close`, `codepoint_to_key`

**Severity:** MEDIUM  *(reduced from HIGH on 2026-04-23; split into sub-items)*  •  **Status:** VERIFIED  •  **Component:** `[support]` `[input]`
**Files:** `src/termisu/log.cr:175-177, 190, 192` + `src/termisu/input/parser.cr:337-341`

> **REVIEW NOTE (2026-04-23):** Original bundled three rescues under one HIGH. After verification, each has different severity:
> - **`log.cr:175-177` empty rescue** — **MEDIUM.** Legitimate bug; STDERR write during setup is safe because setup runs before `enter_alternate_screen` claims the screen.
> - **`log.cr:190, 192` `rescue nil` on close** — **LOW.** Lazy, but only fires on shutdown.
> - **`parser.cr:337-341` bare rescue in `codepoint_to_key`** — **LOW, and the rescue is dead code.** `Key.from_char` is pure hash lookup + case statement; it cannot raise. Remove the rescue rather than narrow it.

#### Verified source

```crystal
# log.cr:156-177 — setup
begin
  file = File.open(file_path, "a")
  file.sync = true
  self.log_file = file
  # ... configure dispatcher ...
  ::Log.setup("*", level, backend)
  Log.info { "Logging initialized: ..." }
rescue ex
  # If we can't open the log file, disable logging silently
end
```

```crystal
# log.cr:186-195 — close
def self.close
  if file = log_file
    if async_mode?
      3.times { Fiber.yield }
      file.flush rescue nil
    end
    file.close rescue nil
    self.log_file = nil
  end
end
```

```crystal
# input/parser.cr:329-345 — codepoint_to_key
private def codepoint_to_key(codepoint : Int32) : Key
  if key = KITTY_CODEPOINTS[codepoint]?
    return key
  end

  if codepoint > 0 && codepoint <= 0x10FFFF
    begin
      Key.from_char(codepoint.chr)
    rescue
      Key::Unknown
    end
  else
    Key::Unknown
  end
end
```

#### Description

Three places swallow exceptions without narrowing the rescue type, violating the project's own rule `.claude/rules/crystal-conventions.md` on exception discipline:

1. **`Logging.setup` (log.cr:175-177):** The rescue body is literally empty. If `File.open(file_path, "a")` fails (permission denied, missing directory, read-only filesystem, sandboxed container), logging silently does not work. Since stdout is reserved for rendering, the user has no way to learn why `TERMISU_LOG_FILE=/tmp/termisu.log` produced nothing.
2. **`Logging.close` (log.cr:190, 192):** `file.flush rescue nil` and `file.close rescue nil`. Bare inline `rescue nil` catches *any* exception type — a `NilAssertionError`, `TypeCastError`, or new Crystal runtime error would be masked.
3. **`codepoint_to_key` (parser.cr:337-341):** `rescue` (no type) catches every `Exception`. The intent is to catch `ArgumentError` from `.chr` on an invalid codepoint, but the range check at line 336 (`codepoint > 0 && codepoint <= 0x10FFFF`) already covers `.chr` validity for non-surrogate cases. Surrogates (0xD800-0xDFFF) slip through the range check but *would* raise — the rescue is the only real defense, and it's too wide.

#### Impact

- **Log hole:** Unwritable log paths in containers, sandboxed shells, or CI environments produce silent failure. Debugging a TUI without logs is miserable because stdout is unavailable.
- **Hidden bugs:** Any future exception thrown inside `file.close` (e.g., from a wrapper refactor) is invisible.
- **Parser fragility:** If `Key.from_char` ever raises something other than `ArgumentError` (bug, OOM, unrelated refactor), input silently maps to `Unknown` and the debugger has nothing to trace.

#### Proposed fix

1. **`Logging.setup`** — emit the failure reason to `STDERR` *before* the TUI takes over (normally `Logging.setup` is called early in `Termisu.new`, well before `enter_alternate_screen`):

   ```crystal
   rescue ex : IO::Error | File::Error
     STDERR.puts "[Termisu] Logging disabled: #{ex.class.name}: #{ex.message}"
     STDERR.flush
     self.setup_error = ex  # class property so callers can inspect programmatically
   end
   ```

2. **`Logging.close`** — narrow to `IO::Error`, matching `SafeFileIO`:

   ```crystal
   file.flush rescue IO::Error
   file.close rescue IO::Error
   ```

3. **`codepoint_to_key`** — explicitly filter surrogates and drop the rescue:

   ```crystal
   private def codepoint_to_key(codepoint : Int32) : Key
     if key = KITTY_CODEPOINTS[codepoint]?
       return key
     end

     return Key::Unknown unless codepoint > 0 && codepoint <= 0x10FFFF
     return Key::Unknown if (0xD800..0xDFFF).includes?(codepoint)  # surrogate halves

     Key.from_char(codepoint.chr)
   end
   ```

#### Verification notes

All three sites read directly and confirmed exactly as quoted. The `Logging.setup` comment explicitly admits "disable logging silently" — the developer knew this was a tradeoff but didn't provide a diagnostic channel.

---

### <a id="termisu-007"></a>TERMISU-007 — `Renderer` abstraction exposes 18 methods; every new attribute ripples across 4 files

**Severity:** HIGH  •  **Status:** VERIFIED  •  **Component:** `[rendering]`
**Files:** `src/termisu/renderer.cr`

#### Description

`Renderer` declares individual abstract methods for every SGR toggle (`enable_bold`, `enable_underline`, `enable_reverse`, `enable_blink`, `enable_dim`, `enable_cursive`, `enable_hidden`, `enable_strikethrough`, `reset_attributes`) plus color ops (`foreground=`, `background=`), cursor ops (`move_cursor`, `show_cursor`, `hide_cursor`), and I/O (`write`, `flush`, `size`, `close`). The interface is not "abstract rendering" — it's "ANSI terminal minus the buffer."

Adding a new attribute today requires changes in `renderer.cr` (new abstract method), `terminal.cr` (implementation), `render_state.cr` (`apply_new_attributes` + `needs_attr?` call), `attribute.cr` (enum member), plus every mock renderer in `spec/support/mock_renderers.cr`.

#### Impact

- Every mock renderer must re-implement 18 methods — test setup is heavy.
- Extension friction: new attributes are a five-file change.
- The abstraction leaks terminal-specific semantics (SGR knowledge) upward.

#### Proposed direction

Narrow to ~6 methods with a `Style` value type:

```crystal
struct Termisu::Style
  getter fg : Color
  getter bg : Color
  getter attr : Attribute

  def initialize(@fg, @bg, @attr)
  end
end

abstract class Termisu::Renderer
  abstract def write(bytes : Bytes | String) : Nil
  abstract def apply_style(style : Style) : Nil
  abstract def move_cursor(x : Int32, y : Int32) : Nil
  abstract def set_cursor_visible(visible : Bool) : Nil
  abstract def flush : Nil
  abstract def size : {Int32, Int32}
  abstract def close : Nil
end
```

Terminal's `apply_style` internally emits SGR for the current style. Buffer's `RenderState` becomes the sole SGR optimizer (bundles with TERMISU-003). Adding a new attribute becomes a one-file change in `attribute.cr` plus a Terminal-internal SGR table update.

#### Verification notes

File is 73 lines; exact method count to be re-checked before the refactor. The llms.txt count of "18 abstract methods" may be off by a handful depending on what counts as a method vs. a setter. Semantic point stands regardless.

---

### <a id="termisu-008"></a>TERMISU-008 — `Termisu::Termisu` facade at ~797 lines with ~60 public methods is becoming a god object

**Severity:** HIGH  •  **Status:** VERIFIED  •  **Component:** `[facade]`
**Files:** `src/termisu/termisu.cr`

#### Description

The facade instantiates Terminal + Reader + Parser + Event::Loop + three event sources (Input, Resize, Timer), and exposes:
- Lifecycle: `new`, `close`, `raw_mode?`, `alternate_screen?`
- Rendering: `set_cell` (×2 overloads via Buffer delegation), `clear`, `render`, `sync`
- Cursor: `set_cursor`, `show_cursor`, `hide_cursor`
- Colors: via delegation (but also direct writers for test)
- Events: `poll_event`, `try_poll_event`, `each_event`, `add_event_source`, `remove_event_source`
- Timers: `enable_timer`, `enable_system_timer`, `disable_timer`, `timer_interval=`, `timer_enabled?`
- Modes: `suspend`, `with_mode`, `with_password_mode`, `with_cbreak_mode`, five variants of mode setters
- Mouse/keyboard: `enable_mouse`, `disable_mouse`, `enable_enhanced_keyboard`, `disable_enhanced_keyboard`
- Misc: `title=`, `sync_updates=`, `emit_mode_change`, `pause_input_processing`

Two unrelated responsibilities are fused: **composition root** (instantiating and wiring the graph) and **facade** (user API). These rarely evolve together, and the mixing makes both harder to test.

#### Impact

- Every new capability adds a method here. No natural stopping point.
- Testing requires a full `Termisu.new`, which opens `/dev/tty` and requires a real terminal.
- Mode-switch orchestration reaches into sibling subsystems (stops `@input_source`, clears `@reader`, re-emits events on `@event_loop.output`) — coupling that's hard to observe in the current structure.

#### Proposed direction

Extract a `Termisu::Session` owning the graph and orchestration:

```
Termisu::Termisu (thin facade, ~150 lines, delegation only)
    └── Termisu::Session (composition + orchestration)
        ├── Terminal
        ├── Reader / Parser
        ├── Event::Loop
        └── ModeCoordinator (mode transitions, pause/resume input)
```

Public API remains on `Termisu::Termisu`; `Session` is internal. The split lets `Session` be built with mocks in tests and evolves mode-transition logic independently from the user-facing surface.

This ticket is a refactor; not scopable as a single PR. Should follow TERMISU-003 / TERMISU-007 since they share the rendering-path surface.

#### Verification notes

Line count approximate — `wc -l` before the fix to confirm current state. Method list is representative; a tree-sitter query or `tldr structure` pass should enumerate the full list before the refactor.

---

### <a id="termisu-009"></a>TERMISU-009 — `Source::Input` blocking `send` causes unbounded latency under backpressure, with possible kernel-level drops

**Severity:** HIGH  •  **Status:** VERIFIED (framing rewritten 2026-04-23)  •  **Component:** `[events]`
**Files:** `src/termisu/event/source/input.cr:103-123`

> **REVIEW NOTE (2026-04-23):** Original title ("keystrokes lost") was imprecise. Actual mechanism: blocking `send` pauses the *producer* fiber, so keystrokes are queued in order but arrive with latency. Under **sustained** backpressure (consumer not draining for seconds), the chain fills: channel (32) → reader buffer (128 B) → kernel TTY buffer (~4 KB) → and only then does the kernel drop. So "loss" is a late-stage symptom, not the primary effect. Fix direction (drop-counter diagnostics + channel cap raise) is still correct; framing is now accurate.

#### Verified source

```crystal
# event/source/input.cr:103-123
while @running.get
  emitted = false
  drained = 0

  while @running.get && drained < MAX_DRAIN_PER_CYCLE
    event = @parser.poll_event(0)
    break unless event

    output.send(event)   # <-- BLOCKING send
    emitted = true
    drained += 1
  end

  break unless @running.get

  if emitted
    Fiber.yield
  else
    sleep IDLE_SLEEP
  end
end
```

#### Description

Input source uses blocking `output.send(event)` on a channel of capacity 32 (`DEFAULT_BUFFER_SIZE = 32` in `event/loop.cr:53`). Timer sources use `send_nonblocking` and self-account drops via `missed_ticks`. The mix is intentional (input wants fidelity, timers want liveness), but the consequences of input's blocking send aren't surfaced to the user.

If the consumer fiber (user's main loop calling `poll_event`) stalls — e.g., slow `render` during a burst, or user paused polling during a long computation — the input fiber blocks on `send` at line 111. With input blocked:
1. Parser stops pulling from Reader.
2. Reader's 4 KB internal buffer fills.
3. Kernel TTY queue fills.
4. Keystrokes are dropped at the kernel boundary (silently).

The 32-event channel + ~4 KB buffer gives maybe 100-500 keystrokes of headroom depending on encoding; after that, drops are silent.

#### Impact

- **Silent data loss.** User types during a long render; some characters vanish. No log, no diagnostic.
- **Paste attacks unmitigated.** A bracketed paste of 10 KB flows through faster than the consumer can process, overwhelms buffering.
- **Hard to diagnose.** Symptoms look like "Termisu sometimes misses keys." Without instrumentation, unfixable.

#### Proposed fix options

**A) Track back-pressure (recommended minimum):** instrument the drop condition and expose a counter:

```crystal
output.send(event)
# after (pseudo — real fix uses select/else + counter):
unless send_nonblocking(output, event)
  @drops.add(1)
  Log.warn { "Input channel full; #{@drops.get} events dropped total" }
end
```

Even if we keep blocking semantics, detect channel-full via a `select/else` probe and log when it happens.

**B) Raise channel capacity.** `DEFAULT_BUFFER_SIZE = 32` → `256`. Trivial change; buys headroom for typical bursts.

**C) Formalize per-source backpressure policy** (ties to TERMISU-023). Add a `Source#delivery_policy : Blocking | DropOldest | DropNew` contract; Loop enforces it uniformly.

Recommend shipping (A) + (B) first, treating (C) as its own refactor.

#### Verification notes

Exact code reproduced above. Channel capacity of 32 confirmed via llms.txt §7.3, to be re-verified in `event/loop.cr` before the fix.

---

### <a id="termisu-010"></a>TERMISU-010 — FFI accepts out-of-range coordinates and codepoints; defense-in-depth hygiene

**Severity:** MEDIUM  *(reduced from HIGH on 2026-04-23)*  •  **Status:** VERIFIED  •  **Component:** `[ffi]`
**Files:** `src/termisu/ffi/conversions.cr:12-16` + `src/termisu/ffi/core.cr:91-103`

> **REVIEW NOTE (2026-04-23):** "DoS via exception spam" framing was overstated. Crystal exceptions aren't Java exceptions — no default stack capture, catch cost is modest. A channel cap of 32 and EINTR retry cap of 100 bound the real-world impact well before exception overhead matters. Still a good defense-in-depth hygiene fix (validate early at FFI boundary), but not HIGH. Also: `Char#chr` already validates surrogates — proposed explicit surrogate check duplicates stdlib logic.

#### Verified source

```crystal
# ffi/conversions.cr:12-16
def self.codepoint_to_char(codepoint : UInt32) : Char
  codepoint.chr
rescue ex : ArgumentError
  raise ArgumentError.new("Invalid Unicode codepoint #{codepoint}: #{ex.message || ex.class.name}")
end
```

#### Description

Untrusted C callers pass coordinates (`x, y : Int32`) and codepoints (`codepoint : UInt32`) through FFI exports. Validation happens *inside* Crystal code paths that raise on bad input:
- `codepoint_to_char` raises `ArgumentError` for surrogates (0xD800-0xDFFF) or out-of-range (> 0x10FFFF).
- `Buffer#set_cell` validates bounds after allocating a `Cell` — Cell allocation is paid before rejection.
- Negative coordinates pass through `Buffer#out_of_bounds?` correctly but a malicious caller paying the exception penalty per invalid call is a DoS lever.

`Guards.with_error_fallback` catches all exceptions and returns a status code — **correct for safety**, but the exception path is ~10-100× slower than a validated rejection, giving a malicious caller an asymmetric cost lever.

#### Impact

- **DoS via exception spam:** A loop calling `termisu_set_cell(ctx, 0, 0, 0xD800, NULL)` burns CPU on exception create/catch/format per call. Against a C consumer in a tight loop, this can monopolize the Crystal runtime.
- **Hot-path exception creation:** `conversions.cr:15` even *rewraps* the ArgumentError with a formatted message, doubling the per-call work.
- **Not exploitable for RCE** — `Guards` correctly shields Crystal state — but it's a performance/availability concern.

#### Proposed fix

Validate cheap at FFI boundary *before* any Crystal work:

```crystal
# ffi/core.cr — in set_cell implementation
def self.set_cell(handle : UInt64, x : Int32, y : Int32, codepoint : UInt32, style_ptr : ...) : Status
  # Fast-fail input validation
  return Status::InvalidArgument if x < 0 || y < 0
  return Status::InvalidArgument if codepoint > 0x10FFFF
  return Status::InvalidArgument if (0xD800_u32..0xDFFF_u32).includes?(codepoint)

  with_context(handle) do |ctx|
    char = codepoint.unsafe_chr  # now guaranteed valid
    # ... existing body ...
  end
end
```

Expose a `Char.valid_scalar?(codepoint : UInt32) : Bool` helper in `conversions.cr` for reuse. Drop the rescue-and-rewrap in `codepoint_to_char` — it's no longer reachable from validated callers, and unvalidated callers shouldn't exist.

#### Verification notes

`conversions.cr` read fully and quoted. `ffi/core.cr` set_cell body should be re-read before patching to ensure the exact error-return path matches the rest of that file's style.

---

### <a id="termisu-011"></a>TERMISU-011 — `Cell` construction + `@batch_buffer.to_s` allocate in diff hot path

**Severity:** HIGH  •  **Status:** VERIFIED  •  **Component:** `[rendering]`
**Files:** `src/termisu/buffer.cr:467, 473` + `src/termisu/cell.cr:92-108`

#### Verified source

```crystal
# buffer.cr:465-474 (inside render_row_batch)
break if back_cell.fg != batch_fg || back_cell.bg != batch_bg || back_cell.attr != batch_attr

@batch_buffer << back_cell.grapheme
columns_advanced += back_cell.width
@front[idx] = back_cell
col += 1
end

render_batch(renderer, batch_start, row, @batch_buffer.to_s, batch_fg, batch_bg, batch_attr, columns_advanced)
```

#### Description

Two hot-path allocations in the render pipeline:

1. **`@batch_buffer.to_s` at line 473.** `IO::Memory#to_s` allocates a fresh `String` for every style batch. Worst case is an alternating-style screen (e.g., syntax-highlighted code) where every cell starts a new batch — 1920 allocations per full-screen render at 60 FPS = 115K strings/sec.
2. **`Cell` construction** (see TERMISU-002 details) — every `set_cell` pays for grapheme iteration + width lookup.

The `@batch_buffer` is reused (it's `clear`ed at line 449), but `to_s` takes a snapshot copy. This is a performance anti-pattern when the downstream consumer (`renderer.write`) could accept the `IO::Memory` directly.

#### Impact

Same frame-budget category as TERMISU-002. Under a full-screen redraw with varied styles, the allocation pressure from `to_s` alone can blow 60 FPS on a 200×50 terminal.

#### Proposed fix

Expose a renderer method that consumes `IO::Memory` without copy:

```crystal
# In Renderer interface (or after narrowing per TERMISU-007):
abstract def write_bytes(io : IO::Memory, byte_count : Int32) : Nil
```

`Terminal` implements it via `LibC.write(fd, io.to_unsafe, byte_count)`. Buffer's render_batch then passes the live buffer:

```crystal
render_batch(renderer, batch_start, row, @batch_buffer, batch_fg, batch_bg, batch_attr, columns_advanced)
```

The `@batch_buffer` is cleared each call (`buffer.cr:449`), so reuse is safe.

#### Verification notes

Confirmed `@batch_buffer.to_s` call at line 473 directly. `IO::Memory#to_s` allocates — this is Crystal stdlib behavior, not library-specific. Fix is straightforward.

---

## MEDIUM

### <a id="termisu-012"></a>TERMISU-012 — ~~`FFI::Registry` generation counter~~ ❌ CLOSED — INVALID

**Severity:** ❌ **CLOSED** *(was MEDIUM; closed on 2026-04-23 review)*  •  **Component:** `[ffi]`
**Files:** `src/termisu/ffi/registry.cr`

> **CLOSURE REASON:** Rejected as overengineering. UInt64 monotonic wrap takes 2^64 operations ≈ 584 billion years at 1 M creates/sec. Handles are never reused in the current design — deleted handles vanish from the map and `fetch(handle)` returns `nil` for stale handles, which is correct. The proposed `{gen, id}` encoding doubles lookup complexity and hash overhead for a problem that cannot manifest in practice. Original ticket text preserved below for historical record.

<details><summary>Original ticket (kept for record)</summary>

#### Verified source

```crystal
# Full registry.cr source:
module Termisu::FFI::Registry
  @@contexts = {} of UInt64 => Termisu::FFI::Context
  @@lock = Mutex.new
  @@next_handle = 1_u64

  def self.insert(context : Termisu::FFI::Context) : UInt64
    @@lock.synchronize do
      handle = @@next_handle
      @@next_handle += 1_u64
      @@contexts[handle] = context
      handle
    end
  end

  def self.fetch(handle : UInt64) : Termisu::FFI::Context?
    @@lock.synchronize { @@contexts[handle]? }
  end

  def self.delete(handle : UInt64) : Termisu::FFI::Context?
    @@lock.synchronize { @@contexts.delete(handle) }
  end
end
```

#### Description

Handles are a monotonically incrementing `UInt64`. On `destroy`, the entry is removed from the map; the counter keeps advancing. In practice, wrap-around takes 2^64 operations (unreachable). But two scenarios still matter:
- **Stale-handle reuse logic**: If a long-lived C caller retains a handle past the lifetime of its context, and the registry is ever reset (or the process re-creates contexts aggressively), there is no structural prevention against the handle being reassigned to a *new* context.
- **Cross-process confusion:** If a future feature shares handles across processes or serializes them, collisions become real.

#### Impact

Low in the current single-process design; MEDIUM because the fix is cheap and strictly improves safety.

#### Proposed fix

Encode a generation counter in the upper 32 bits:

```crystal
module Termisu::FFI::Registry
  @@contexts = {} of UInt32 => {UInt32, Termisu::FFI::Context}  # id => {gen, ctx}
  @@lock = Mutex.new
  @@next_id = 1_u32
  @@generations = {} of UInt32 => UInt32

  def self.insert(context) : UInt64
    @@lock.synchronize do
      id = @@next_id
      @@next_id += 1_u32
      gen = (@@generations[id]? || 0_u32) + 1_u32
      @@generations[id] = gen
      @@contexts[id] = {gen, context}
      (gen.to_u64 << 32) | id.to_u64
    end
  end

  def self.fetch(handle : UInt64) : Termisu::FFI::Context?
    @@lock.synchronize do
      id = (handle & 0xFFFFFFFF_u64).to_u32
      gen = (handle >> 32).to_u32
      if entry = @@contexts[id]?
        entry[0] == gen ? entry[1] : nil
      end
    end
  end
end
```

#### Verification notes

Full file read; confirmed no generation tracking. 23-line file, simple to modify. Low-risk change.

---

### <a id="termisu-013"></a>TERMISU-013 — Input parser has no CPU budget — malformed CSI spam can monopolize the input fiber

**Severity:** MEDIUM  •  **Status:** NEEDS-REPRO  •  **Component:** `[input]`
**Files:** `src/termisu/input/parser.cr:196-228`

#### Description

`parse_csi_sequence` reads bytes until a final byte in 0x40-0x7E, bounded by `MAX_SEQUENCE_LENGTH`. A malicious or malfunctioning TTY producer (compromised keyboard firmware, malicious tmux plugin, paste injection) can send repeated unterminated CSI prefixes: `\e[AAAA\e[AAAA…`. Each consumes up to `MAX_SEQUENCE_LENGTH` bytes before returning `Key::Unknown`. No aggregate rate limit exists.

#### Impact

CPU DoS against the input fiber. Over time, bytes accumulate in Reader's buffer and TTY queue, and the parser fiber eats CPU without producing meaningful events. Realistic attack vector is limited to cases where an attacker controls the tty's upstream (SSH-forwarded session with compromised intermediate, malicious terminal emulator, paste-injection via a malicious program).

#### Proposed fix

Introduce a byte budget per-second on the input fiber. When exceeded, log a warning and briefly back off. Detailed design tbd — see TERMISU-023 for the related "uniform policy" work.

#### Verification notes

Source region was not re-read for this ticket (marked NEEDS-REPRO). The scope of `MAX_SEQUENCE_LENGTH` and its enforcement should be verified before implementing a fix.

---

### <a id="termisu-014"></a>TERMISU-014 — Terminfo binary parser's null-terminated string scan lacks end-of-data guard

**Severity:** MEDIUM  •  **Status:** NEEDS-REPRO  •  **Component:** `[terminfo]`
**Files:** `src/termisu/terminfo/parser.cr:247-263` (approximate, per scout review)

#### Description

`read_null_terminated_string` scans until a NUL byte. If a malformed terminfo file contains a string offset pointing into the last region of the table without a NUL terminator, the scan runs past `@data.size`. Out-of-bounds read in Crystal raises `IndexError`, which is preferable to UB but still a DoS path (crash on first read of an attacker-crafted terminfo file).

#### Impact

- A user runs in a directory where a malicious `~/.terminfo` or `$TERMINFO` override places a crafted file matching `$TERM`. On Termisu initialization, parser reads that file and crashes.
- Not exploitable for code execution in Crystal (bounds checking), but a reliable crash vector.

#### Proposed fix

Add an explicit guard at each read step:

```crystal
while io.pos < @data.size
  byte = io.read_byte
  break if byte.nil? || byte == 0
  buffer << byte.chr
end
```

Or use `String.new` with an explicit end position derived from the table bounds.

#### Verification notes

Scout review identified the specific lines but this ticket has not been re-verified against the current `parser.cr`. Before fixing, read lines 240-270 of that file to confirm the exact loop structure.

---

### <a id="termisu-015"></a>TERMISU-015 — `Color.ansi8(-1)` is silently valid; docstring and validator disagree

**Severity:** MEDIUM  •  **Status:** VERIFIED  •  **Component:** `[color]`
**Files:** `src/termisu/color.cr:57-67, 101-103`

#### Verified source

```crystal
# color.cr:56-67
DEFAULT_INDEX = -1

protected def initialize(@mode : Mode, @index : Int32 = 0, @r : UInt8 = 0_u8, @g : UInt8 = 0_u8, @b : UInt8 = 0_u8)
end

# Creates an ANSI-8 basic color (0-7).
def self.ansi8(index : Int32) : Color
  Validator.validate_ansi8(index)
  new(Mode::ANSI8, index: index)
end

# color.cr:100-103
def self.default : Color
  ansi8(DEFAULT_INDEX)
end
```

#### Description

The public factory `Color.ansi8(index)` has a docstring stating "0-7" as the valid range. `Color.default` calls `ansi8(DEFAULT_INDEX)` where `DEFAULT_INDEX = -1`. For this to succeed, `Validator.validate_ansi8` must accept `-1` — and it does (verifiable by running `Color.default`, which doesn't raise). So the *actual* valid range is `{-1} ∪ {0..7}`, but the docstring lies.

External consumers passing `-1` intentionally get undefined semantics (it happens to mean "default color" today, but that's an implementation detail leaking through a validated factory).

#### Impact

- Doc/code drift — readers can't trust the stated range.
- Internal sentinel (`DEFAULT_INDEX = -1`) leaks through the public API.

#### Proposed fix

Bypass the public factory in `Color.default` and tighten the validator:

```crystal
def self.default : Color
  new(Mode::ANSI8, index: DEFAULT_INDEX)  # direct, no validation
end

# In validator — enforce the stated range strictly:
def self.validate_ansi8(index : Int32) : Nil
  raise ArgumentError.new("ANSI-8 index must be 0-7, got #{index}") unless (0..7).includes?(index)
end
```

`Color.default` still works because it uses `new` directly. External callers who accidentally pass `-1` now get a clean ArgumentError.

#### Verification notes

`color.cr` lines 1-110 read directly. Docstring at line 63 is unambiguous. The validator file (`color/validator.cr`) should be inspected before the fix to confirm the current check logic.

---

### <a id="termisu-016"></a>TERMISU-016 — `set_cursor(x, y, visible: Bool? = true, …)` has confusing precedence and default

**Severity:** MEDIUM  •  **Status:** NEEDS-REPRO  •  **Component:** `[facade]`
**Files:** `src/termisu/termisu.cr:165-176` (per scout review)

#### Description

Per scout review, the signature is `set_cursor(x, y, visible : Bool? = true, …)`. The body contains a conditional like `visible ? show_cursor : hide_cursor unless visible.nil?`, which parses with surprising precedence. Combined with a default of `true` (not `nil`), every default call shows the cursor — no way to say "move cursor but don't touch visibility" without passing `visible: nil` explicitly, which isn't obvious from the docstring.

#### Impact

API confusion. Users who want to set position without changing visibility must read the source to discover the `nil` idiom.

#### Proposed fix

Split into two methods or change the default:

```crystal
# Simpler: position only, doesn't change visibility
def set_cursor(x : Int32, y : Int32) : Nil
  @terminal.move_cursor(x, y)
end

# Explicit visibility change
def set_cursor(x : Int32, y : Int32, *, visible : Bool, blink : Bool? = nil, shape : Cursor::Shape? = nil) : Nil
  @terminal.move_cursor(x, y)
  visible ? @terminal.show_cursor : @terminal.hide_cursor
  # ... apply blink / shape if present
end
```

#### Verification notes

Not re-verified against the current source. Before fixing, read `termisu.cr:160-180` to confirm exact signature and precedence.

---

### <a id="termisu-017"></a>TERMISU-017 — `terminal.cr` at ~699 lines mixes SGR, modes, mouse, enhanced keyboard, title, sync updates

**Severity:** MEDIUM  •  **Status:** NEEDS-REPRO  •  **Component:** `[rendering]`
**Files:** `src/termisu/terminal.cr`

#### Description

One class handles: alternate-screen, cached SGR emission (fg/bg/attr), mouse enable/disable (X10 + 1006 SGR), enhanced keyboard (Kitty + modifyOtherKeys), sync updates (BSU/ESU), window title, mode switching, cursor delegation, and Buffer delegation. Constants for escape sequences (`MOUSE_ENABLE_SGR`, `KITTY_KEYBOARD_ENABLE`, `BSU`, `ESU`) are scattered mid-class rather than grouped at top per the project's own `crystal-conventions.md` rule.

#### Impact

- Hard to find anything. Extension friction.
- Violates the canonical class order documented in `.claude/rules/crystal-conventions.md`.

#### Proposed direction

Extract:
- `Terminal::Protocols` — constants for mouse and enhanced keyboard sequences
- `Terminal::SyncUpdate` — BSU/ESU logic
- Keep `terminal.cr` under 400 lines focused on buffer/render/cursor delegation + mode orchestration

#### Verification notes

Line count approximate. Run `wc -l src/termisu/terminal.cr` before the fix.

---

### <a id="termisu-018"></a>TERMISU-018 — `SHUTDOWN_TIMEOUT_MS = 100` but code sleeps `/ 10` (10 ms) — name lies

**Severity:** MEDIUM  •  **Status:** NEEDS-REPRO  •  **Component:** `[events]`
**Files:** `src/termisu/event/loop.cr:54-56, 155` (per scout review)

#### Description

Per scout review, `SHUTDOWN_TIMEOUT_MS = 100` is declared, but `stop` calls `sleep SHUTDOWN_TIMEOUT_MS.milliseconds / 10` — 10 ms, not 100 ms. Name implies 100 ms is the budget; only 10% is used.

#### Impact

Reader confusion. Someone trying to tune shutdown responsiveness will change `SHUTDOWN_TIMEOUT_MS` and see no linear effect.

#### Proposed fix

Rename to reflect the actual value:

```crystal
SHUTDOWN_FIBER_GRACE = 10.milliseconds
# ... in stop:
sleep SHUTDOWN_FIBER_GRACE
```

Drop the `/10` ceremony.

#### Verification notes

Not re-verified. Read `event/loop.cr:50-160` before fixing to confirm the pattern.

---

### <a id="termisu-019"></a>TERMISU-019 — CSI parser uses `params.split(';')` — allocates Array+Strings per special key

**Severity:** MEDIUM  •  **Status:** VERIFIED  •  **Component:** `[input]`
**Files:** `src/termisu/input/parser.cr:349-357`

#### Verified source

```crystal
# input/parser.cr:349-357
private def parse_modifiers(params : String) : Modifier
  return Modifier::None unless params.includes?(';')

  parts = params.split(';')   # <-- allocates Array + N Strings per call
  return Modifier::None if parts.size < 2

  mod_code = parts[1].to_i? || 1
  Modifier.from_xterm_code(mod_code)
end
```

#### Description

Every CSI sequence with a modifier field (arrow keys with modifiers, F-keys, Kitty protocol, modifyOtherKeys) allocates an Array of Strings via `split`. Called on every special keypress. Rapid nav (holding an arrow key) generates hundreds of allocations per second.

Two other sites use the same pattern (scout-identified lines 243 and 275 in `decode_csi_key` and `parse_kitty_key`).

#### Impact

Allocation pressure during fast keyboard navigation. Not catastrophic but easy to eliminate.

#### Proposed fix

In-place parse without splitting:

```crystal
private def parse_modifiers(params : String) : Modifier
  semicolon = params.index(';')
  return Modifier::None unless semicolon

  mod_code = 0
  i = semicolon + 1
  while i < params.bytesize
    ch = params.unsafe_byte_at(i)
    break if ch < 48 || ch > 57  # non-digit
    mod_code = mod_code * 10 + (ch - 48)
    i += 1
  end
  return Modifier::None if mod_code == 0
  Modifier.from_xterm_code(mod_code)
end
```

Apply same pattern at `parser.cr:243, 275` once those regions are re-verified.

#### Verification notes

`parse_modifiers` read directly and confirmed. Other two sites are plausible from context but not re-verified — check before applying.

---

### <a id="termisu-020"></a>TERMISU-020 — `apply_attribute_change` does 2×8 `includes?` checks per style change

**Severity:** MEDIUM  •  **Status:** VERIFIED  •  **Component:** `[rendering]`
**Files:** `src/termisu/render_state.cr:93-107`

#### Verified source

```crystal
# render_state.cr:93-107
private def apply_new_attributes(renderer : Renderer, new_attr : Attribute)
  renderer.enable_bold if needs_attr?(new_attr, Attribute::Bold)
  renderer.enable_underline if needs_attr?(new_attr, Attribute::Underline)
  renderer.enable_reverse if needs_attr?(new_attr, Attribute::Reverse)
  renderer.enable_blink if needs_attr?(new_attr, Attribute::Blink)
  renderer.enable_dim if needs_attr?(new_attr, Attribute::Dim)
  renderer.enable_cursive if needs_attr?(new_attr, Attribute::Cursive)
  renderer.enable_hidden if needs_attr?(new_attr, Attribute::Hidden)
  renderer.enable_strikethrough if needs_attr?(new_attr, Attribute::Strikethrough)
end

private def needs_attr?(new_attr : Attribute, flag : Attribute) : Bool
  new_attr.includes?(flag) && !@attr.includes?(flag)
end
```

#### Description

`needs_attr?` performs two `Attribute#includes?` calls (each a bitwise AND) per attribute flag, 8 times, giving 16 bitwise ops + branch predictions per style transition.

#### Impact

Not enormous, but called in the render hot path. Trivially optimizable.

#### Proposed fix

Compute the delta once:

```crystal
private def apply_new_attributes(renderer : Renderer, new_attr : Attribute)
  added = new_attr & ~@attr  # bits newly enabled
  renderer.enable_bold          if added.bold?
  renderer.enable_underline     if added.underline?
  renderer.enable_reverse       if added.reverse?
  renderer.enable_blink         if added.blink?
  renderer.enable_dim           if added.dim?
  renderer.enable_cursive       if added.cursive?
  renderer.enable_hidden        if added.hidden?
  renderer.enable_strikethrough if added.strikethrough?
end
```

Eight bitwise ops total; same logic. Drops `needs_attr?`. Will bundle naturally with the TERMISU-007 / TERMISU-003 refactor.

#### Verification notes

Full source reproduced and confirmed.

---

### <a id="termisu-021"></a>TERMISU-021 — `ffi/core.cr` is a grab-bag file mirroring the facade's bloat

**Severity:** MEDIUM  •  **Status:** NEEDS-REPRO  •  **Component:** `[ffi]`
**Files:** `src/termisu/ffi/core.cr`

#### Description

Per llms.txt inventory, `ffi/core.cr` contains every Crystal-side implementation of every FFI export — lifecycle, size, rendering, cursor, cells, events, timers, mouse, enhanced keyboard, modes. It's effectively a parallel facade with `with_context { ... }` boilerplate wrapping each call.

#### Impact

Mirrors TERMISU-008's facade bloat — a refactor of one should drive the other. Adding an FFI export today means editing both `exports.cr` and `core.cr` in ad-hoc locations.

#### Proposed direction

Split by subsystem: `ffi/rendering.cr`, `ffi/events.cr`, `ffi/modes.cr`, `ffi/lifecycle.cr`. Or — better — generate the Crystal-side dispatchers from annotations on the facade, making drift structurally impossible.

#### Verification notes

File structure described from llms.txt. Read `ffi/core.cr` to confirm current organization before splitting.

---

### <a id="termisu-022"></a>TERMISU-022 — Crystal `Color::Mode` lacks `Default`; ABI `ColorMode` has it — asymmetric contract

**Severity:** MEDIUM  •  **Status:** VERIFIED  •  **Component:** `[color]` `[ffi]`
**Files:** `src/termisu/color.cr:40-57` + `src/termisu/ffi/color_mode.cr` (per scout review)

#### Verified source

```crystal
# color.cr:40-57
enum Mode
  ANSI8   # Basic 8 colors (0-7)
  ANSI256 # Extended 256-color palette
  RGB     # 24-bit true color
end

getter mode : Mode
getter index : Int32
getter r : UInt8
getter g : UInt8
getter b : UInt8

DEFAULT_INDEX = -1
```

#### Description

Crystal-side `Color::Mode` has 3 variants: `ANSI8`, `ANSI256`, `RGB`. "Default color" is encoded by `Mode::ANSI8` with `index == -1`. The ABI's `ColorMode` enum (per llms.txt §9.5) has 4 variants: `Default=0`, `Ansi8=1`, `Ansi256=2`, `Rgb=3` — so the ABI treats `Default` as a first-class mode.

`conversions.cr:28-41` handles this by dispatching on ABI mode and calling `Color.default` for mode 0, `Color.ansi8(color.index)` for mode 1, etc. That works, but:

1. Adding a new mode (e.g., Oklab) requires edits in `color.cr` (enum + validator + conversions + SGR emitter in Terminal) + `ffi/color_mode.cr` + `ffi/conversions.cr`.
2. The Crystal Mode vs. ABI ColorMode asymmetry is a trap — a reader seeing the ABI form might infer Crystal has a Default mode too.

#### Impact

Friction on future color-mode additions. Subtle landmine for contributors.

#### Proposed fix

Unify: add `Default` to Crystal's Mode enum, drop `DEFAULT_INDEX`:

```crystal
enum Mode
  Default
  ANSI8
  ANSI256
  RGB
end

def self.default : Color
  new(Mode::Default)
end
```

`Color.default?` predicate becomes `mode == Mode::Default` instead of `index == -1`. `Terminal#foreground=` dispatch adds a new arm for `Default` → emit `\e[39m`. ABI conversion becomes 1-to-1.

#### Verification notes

Crystal side confirmed directly. ABI enum should be re-read in `ffi/color_mode.cr` to ensure exact variant list.

---

### <a id="termisu-023"></a>TERMISU-023 — Backpressure policy is scattered across sources, not uniform in the Loop

**Severity:** MEDIUM  •  **Status:** VERIFIED  •  **Component:** `[events]`
**Files:** `src/termisu/event/loop.cr` + all `event/source/*.cr`

#### Description

One shared channel, three different backpressure policies:
- `Source::Input` (confirmed at `source/input.cr:111`) uses blocking `send` — see TERMISU-009.
- `Source::Timer` and `Source::SystemTimer` use `send_nonblocking` (inherited helper) and self-account drops as `missed_ticks`.
- `Termisu::Termisu#emit_mode_change` (per scout review) sends to the same channel — yet another site with its own policy.

Three sites, three policies, no uniform contract.

#### Impact

- Adding a new source requires answering "what's my backpressure policy?" from scratch.
- Per-source prioritization (e.g., "always deliver Resize, drop Ticks before Key") cannot be expressed in the current design.
- Reasoning about `poll_event` behavior under load requires reading every source and every facade send site.

#### Proposed direction

Lift the policy into the `Source` contract:

```crystal
abstract class Termisu::Event::Source
  enum DeliveryPolicy
    Blocking         # block the source fiber if channel full (input's current behavior)
    DropOldest       # drop oldest queued event (timer's current behavior via missed_ticks)
    DropNew          # drop the new event silently
    DropWithCounter  # drop + increment counter for diagnostics
  end

  abstract def delivery_policy : DeliveryPolicy
  # ... existing abstract methods ...
end
```

`Event::Loop` enforces the policy at send time; sources stop owning `send_nonblocking` logic. Also enables per-priority ordering: high-priority sources could get their own small channel that the loop merges into the main one with priority.

This is a refactor; not scopable as a small PR. Bundle with TERMISU-009.

#### Verification notes

`Source::Input` blocking send confirmed directly. Other sources' policies summarized from llms.txt; re-verify against each file before patching.

---

### <a id="termisu-024"></a>TERMISU-024 — `Buffer#invalidate` relies on implicit "NUL is never a real cell" contract

**Severity:** MEDIUM  •  **Status:** NEEDS-REPRO  •  **Component:** `[rendering]`
**Files:** `src/termisu/buffer.cr:200-210` (per scout review)

#### Description

Per scout review, `Buffer#invalidate` fills `@front` with `Cell.new(" ", …)` as a sentinel guaranteed to differ from any valid cell (which never contains a NUL byte because `Buffer#set_cell` rejects it via `control_char?`). The invariant "NUL never appears in a valid cell" lives in two places:
- Fill site in `invalidate`
- Guard at `set_cell_internal` in `buffer.cr:326-329`

If `control_char?` is ever relaxed (e.g., to allow some C0 controls for box drawing), the invalidation mechanism silently breaks.

#### Impact

A distant change can silently disable full-screen redraws — an almost-invisible bug that manifests as "screen doesn't refresh after resize in some edge case."

#### Proposed fix

Use a structural sentinel rather than a value-based one:

```crystal
# Option A: Array(Cell?) with nil meaning "unknown"
@front : Array(Cell?) = Array(Cell?).new(size, nil)

# Option B: explicit Cell::Invalid variant
struct Cell
  class_getter invalid : Cell = Cell.new(valid: false)
end
```

#### Verification notes

Not re-verified. Read `buffer.cr:195-335` before fixing.

---

### <a id="termisu-025"></a>TERMISU-025 — `Cell` struct fuses display data with grid-occupancy (continuation)

**Severity:** MEDIUM  •  **Status:** VERIFIED  •  **Component:** `[rendering]`
**Files:** `src/termisu/cell.cr:42-48`

#### Verified source

```crystal
# cell.cr:42-48
struct Termisu::Cell
  getter grapheme : String = ""
  getter width : UInt8 = 0
  getter? continuation : Bool
  property fg : Color
  property bg : Color
  property attr : Attribute
```

#### Description

`Cell` carries both display data (grapheme, fg, bg, attr) and grid-occupancy data (`continuation`). Buffer's logic has many `cell.continuation?` checks and must clear pairs together. Two concepts — "logical character" and "physical slot" — are fused in one struct, which leaks grid semantics into the value type.

#### Impact

- Callers of Cell's public API see `continuation?` even though they can't meaningfully set it (continuation cells are constructed via `Cell.continuation`).
- Wide-char invariants are enforced in Buffer code rather than structurally.

#### Proposed direction

Move occupancy to Buffer-internal representation:

```crystal
private enum Slot
  Glyph(Cell)
  Continuation(prev_x : Int16)
  Empty
end

@front : Array(Slot)
@back  : Array(Slot)
```

`Cell` becomes a pure display record. Buffer's invariants (e.g., "writing a narrow char over a wide-char leading slot clears both slots") become easier to enforce and test.

Refactor in scope; bundle with TERMISU-024 since both touch Buffer's storage model.

#### Verification notes

Source confirmed directly.

---

### <a id="termisu-026"></a>TERMISU-026 — `Reader` buffer is 128 bytes — undersized for burst input

**Severity:** MEDIUM  •  **Status:** NEEDS-REPRO  •  **Component:** `[io]`
**Files:** `src/termisu/reader.cr`

#### Description

The llms.txt indexing claims 4096 bytes; the performance reviewer read 128 bytes. Discrepancy — reality needs to be re-verified directly. If the buffer is indeed 128 bytes:
- A paste of a multi-line sequence (100+ bytes) requires multiple `read()` syscalls.
- Fast typing (~1000 keys/sec burst, each 1-3 bytes) takes ~8-10 syscalls/sec.

Either way, the buffer size is a tuning knob worth re-visiting.

#### Impact

Mild syscall amplification under burst input.

#### Proposed fix

If buffer is 128 bytes: raise to 4096 (page-aligned, matches many stdlib defaults). If already 4096: nothing to do; close this ticket.

#### Verification notes

**MUST verify the actual buffer size in `reader.cr` before acting** — llms.txt and the performance review disagree. One source must be wrong.

---

### <a id="termisu-027"></a>TERMISU-027 — `Event::Source` invariants are documented but unenforced

**Severity:** MEDIUM  •  **Status:** NEEDS-REPRO  •  **Component:** `[events]`
**Files:** `src/termisu/event/source.cr`

#### Description

llms.txt §7.2 states that every `Event::Source` implementation must:
1. Use `Atomic(Bool) + compare_and_set` for idempotent lifecycle.
2. Rescue `Channel::ClosedError` gracefully in `run_loop`.

Neither invariant is enforced by the abstract class — a subclass can set `@running = true` directly (non-atomic) or omit the rescue, violating the contract silently.

#### Impact

- Custom sources (a declared extension point) are at the mercy of the implementer to get the invariants right.
- A subtle concurrency bug in a custom source is nearly impossible to diagnose without knowing the contract.

#### Proposed direction

Template-method the lifecycle in the base class:

```crystal
abstract class Termisu::Event::Source
  @running = Atomic(Bool).new(false)

  def start(output : Channel(Event::Any)) : Nil
    return unless @running.compare_and_set(false, true)
    spawn(name: name) do
      begin
        run(output)
      rescue Channel::ClosedError
        # expected on shutdown
      ensure
        @running.set(false)
      end
    end
  end

  def stop : Nil
    return unless @running.compare_and_set(true, false)
  end

  def running? : Bool
    @running.get
  end

  abstract def name : String
  abstract def run(output : Channel(Event::Any)) : Nil
end
```

Existing subclasses override `run` instead of `start`/`stop`. Contract is now structural.

#### Verification notes

`Event::Source` base class should be re-read before fixing to confirm current abstract surface. All four existing sources will need minor updates.

---

## LOW

### <a id="termisu-028"></a>TERMISU-028 — `Terminfo` pre-caches 12 capabilities at ctor; list is hardcoded

**Severity:** LOW  •  **Status:** VERIFIED (via llms.txt §2.6)  •  **Component:** `[terminfo]`
**Files:** `src/termisu/terminfo.cr:29-41, 42-66`

#### Description

12 capabilities are cached as instance vars (`@cached_cup`, `@cached_setaf`, …) at ctor. Always paid, list is hardcoded, new hot capabilities require editing `cache_frequent_capabilities` plus the instance-var list.

#### Proposed fix

Replace with lazy memo on first access, OR profile to see if the cache is even worth keeping (a `@caps : Hash` lookup is O(1) and may be fast enough).

---

### <a id="termisu-029"></a>TERMISU-029 — FFI layer is unconditionally compiled — no opt-out flag

**Severity:** LOW  •  **Status:** VERIFIED (via llms.txt §12.12)  •  **Component:** `[ffi]`
**Files:** `src/termisu/ffi.cr`

#### Description

`require "./ffi/*"` is unconditional. Consumers building small CLI tools pay for 15 extra files and their exported symbols.

#### Proposed fix

```crystal
# In ffi.cr:
{% if flag?(:termisu_ffi) %}
  require "./ffi/version"
  require "./ffi/status"
  # ... etc.
{% end %}
```

Document the flag. Default off for executables, on for shared-library builds.

---

### <a id="termisu-030"></a>TERMISU-030 — `TIOCGWINSZ` magic numbers duplicated per-platform without shared source

**Severity:** LOW  •  **Status:** NEEDS-REPRO  •  **Component:** `[io]`
**Files:** `src/termisu/terminal/backend.cr:192-201` (per scout review)

#### Description

Platform-specific ioctl constants (`0x5413`, `0x40087468`) are defined via `{% unless LibC.has_constant? %}` guards, duplicated across files (termios has similar NCCS handling).

#### Proposed fix

Consolidate into `src/termisu/lib_c/ioctl.cr`, parallel to existing `lib_c/kqueue.cr`. Include a comment citing the header each value originates from.

---

### <a id="termisu-031"></a>TERMISU-031 — `Terminfo#to_status_line_seq` hardcodes sequence; should fallback to `get_cap`

**Severity:** LOW  •  **Status:** NEEDS-REPRO  •  **Component:** `[terminfo]`
**Files:** `src/termisu/terminfo.cr:119-126` (per scout review)

#### Description

Comment says "tsl and fsl apparently tend to be missing, so we're hardcoding them." But a terminal that *does* provide custom `tsl`/`fsl` is silently ignored.

#### Proposed fix

```crystal
def to_status_line_seq : String
  get_cap("tsl").presence || "\e]0;"
end

def from_status_line_seq : String
  get_cap("fsl").presence || "\a"
end
```

---

### <a id="termisu-032"></a>TERMISU-032 — `Terminal#title=` has non-idiomatic setter return pattern

**Severity:** LOW  •  **Status:** NEEDS-REPRO  •  **Component:** `[rendering]`
**Files:** `src/termisu/terminal.cr:692-696` (per scout review)

#### Description

Per scout review, `title=` has two return paths: an early `return title` when unchanged, and an implicit return of the assignment. Crystal setters conventionally return `Nil`. Missing docstring and return type annotation.

#### Proposed fix

```crystal
def title=(new_title : String) : Nil
  return if new_title == @title
  @title = new_title
  # ... write escape sequence ...
end
```

---

### <a id="termisu-033"></a>TERMISU-033 — `Attribute::Italic` is a documented alias for `Cursive`; `.to_s` always reports `"Cursive"`

**Severity:** LOW  •  **Status:** VERIFIED-MODIFIED (reclassified from HIGH)  •  **Component:** `[rendering]`
**Files:** `src/termisu/attribute.cr:30-34`

#### Verified source

```crystal
# attribute.cr:30-34
# Italic/cursive text (not supported on all terminals)
Cursive = 32

# Alias for Cursive (more common name)
Italic = 32
```

#### Description

The analysis originally flagged this as HIGH, expecting a bug. On inspection, the code comment at line 33 **explicitly documents** that `Italic` is an alias for `Cursive`. The intent is clear: keep both names for API ergonomics, but `Cursive` is canonical.

However, one real consequence remains: `(Attribute::Italic).to_s` returns `"Cursive"` because Crystal's `@[Flags]` enum reports the first-declared name for duplicate values. User code logging `Attribute::Italic` will see `"Cursive"` in logs — cosmetic surprise.

Reclassified from HIGH to LOW because:
- Behavior is documented.
- No functional bug (`Italic == Cursive`, both compose correctly with `|`).
- Only a log/serialization cosmetic artifact.

#### Proposed fix (optional)

Pick one canonical name across the codebase (Italic is more widely recognized in modern tooling). If canonicalizing to `Italic`:
- Declare `Italic = 32` first, `Cursive = 32` second.
- Rename `Renderer#enable_cursive` → `enable_italic` (and mock implementations).
- `RenderState`'s `apply_new_attributes` line 99 uses `Attribute::Cursive` — update to `Italic`.

If staying with Cursive as canonical (current state), document more prominently in the Attribute top-of-file docstring that `Italic.to_s == "Cursive"` is expected.

#### Verification notes

Full enum reproduced. Comment at line 33 is explicit — the analysis reviewer over-reacted. Keeping the ticket because the `.to_s` cosmetic is real and the renderer naming inconsistency (`enable_cursive` vs `Attribute::Italic` when canonicalizing) is legitimate polish work.

---

### <a id="termisu-034"></a>TERMISU-034 — Three `# ameba:disable Naming/AccessorMethodName` suppressions without justification

**Severity:** LOW  •  **Status:** NEEDS-REPRO  •  **Component:** `[rendering]`
**Files:** `src/termisu/terminal.cr:315-316`, `src/termisu/terminal/backend.cr:135-136`, `src/termisu/termios.cr:79-80` (per scout review)

#### Description

Three locations disable the ameba warning for `set_mode(mode : …)` (ameba wants `mode=`). Suppressions lack a justifying comment. Per `.claude/rules/crystal-conventions.md`, accumulated lint suppressions should be justified inline.

#### Proposed fix

Either:
1. Rename to `mode=` project-wide (more idiomatic; keeps `current_mode` getter for read).
2. Add `# ameba:disable Naming/AccessorMethodName — kept for symmetry with current_mode getter; see docs/terminal-modes.md`

Pick (1) unless there's a specific reason to keep `set_mode`.

---

### <a id="termisu-035"></a>TERMISU-035 — `$TERM` is used unvalidated in file path construction (defense-in-depth)

**Severity:** LOW  •  **Status:** NEEDS-REPRO  •  **Component:** `[terminfo]`
**Files:** `src/termisu/terminfo/database.cr`

#### Description

`Database` constructs paths from `$TERM` via `File.join(base, @name[0].to_s, @name)`. If `$TERM` contained path separators, path construction could traverse outside the expected directory. In practice `$TERM` is user-controlled, so this isn't an escalation vector; it's defense-in-depth only.

#### Proposed fix

Validate `@name` against `/\A[a-zA-Z0-9_+-]+\z/` (typical terminal name charset) early:

```crystal
def initialize(@name : String)
  unless @name.matches?(/\A[a-zA-Z0-9_+-]+\z/)
    raise ArgumentError.new("Invalid terminal name: #{@name.inspect}")
  end
end
```

---

### <a id="termisu-036"></a>TERMISU-036 — `Reader` EINTR retry loop can exhaust `MAX_EINTR_RETRIES = 100` under signal storm

**Severity:** MEDIUM  •  **Status:** NEEDS-REPRO  •  **Component:** `[io]`
**Files:** `src/termisu/reader.cr:251-298` (per security review)

#### Description

`Reader#fill_buffer` retries up to `MAX_EINTR_RETRIES = 100` on EINTR before raising `IOError`. Similar retry loops exist in `check_fd_readable_select` and the poll variant. A sibling process sending signals at high rate (accidental fork-bomb, adversarial process on a shared machine, misconfigured cron) interrupts each `read()` and walks the counter to zero quickly. After 100 consecutive interruptions, the input pipeline raises — the Source::Input fiber exits, and further input is dead until Termisu is restarted.

Not a remote-exploit concern (requires local process sending signals to the Termisu process), but a real reliability hole for long-running TUIs on busy systems.

#### Impact

- Long-running TUIs (monitoring dashboards, editors, system tools) can lose input under load from an unrelated process.
- The exhaustion raises a bare `IOError` that may not be surfaced cleanly to the application.

#### Proposed fix

Two layers:
1. **Exponential backoff between EINTR retries:** after a threshold (say, 10 consecutive EINTRs), add `Fiber.yield` / `sleep 1.millisecond` with doubling backoff. This prevents the retry loop from burning the full counter in microseconds.
2. **Don't raise on exhaustion; log and yield:** replace the final `raise IOError` with a logged warning + return `nil` (no-data-available). The input fiber stays alive and retries on the next tick.

```crystal
MAX_EINTR_RETRIES = 100
EINTR_BACKOFF_THRESHOLD = 10

private def fill_buffer
  retries = 0
  loop do
    n = LibC.read(@fd, @buffer.to_unsafe, @buffer.size)
    if n < 0
      err = Errno.value
      if err == Errno::EINTR
        retries += 1
        if retries >= MAX_EINTR_RETRIES
          Log.warn { "Reader: EINTR storm (100 consecutive); yielding instead of failing" }
          Fiber.yield
          return nil
        end
        sleep 1.millisecond if retries >= EINTR_BACKOFF_THRESHOLD
        next
      end
      raise Error.read_failed(err)
    end
    @buffer_pos = 0
    @buffer_len = n.to_i32
    return n
  end
end
```

#### Verification notes

Code region was not re-read for this ticket. Must inspect `reader.cr:240-300` before fixing — the exact structure of the EINTR loop and the naming of constants should be confirmed. The `MAX_EINTR_RETRIES = 100` constant is per security review.

---

### <a id="termisu-037"></a>TERMISU-037 — `Reader#close` does not close the fd; ownership model undocumented

**Severity:** MEDIUM  •  **Status:** NEEDS-REPRO  •  **Component:** `[io]`
**Files:** `src/termisu/reader.cr:240-244` (per quality review)

#### Description

Per quality review, `Reader#close` has a docstring: "Closes the reader (does not close the file descriptor)." This is a surprising lifecycle for a resource-holding class — callers who expect RAII-style fd ownership will leak. The fd is actually owned by `TTY` (which the facade owns), but that chain isn't explained at the Reader level.

#### Impact

- A test or direct user of `Reader` (bypassing the facade) that constructs a Reader + expects `close` to release the fd will leak.
- Inconsistent with other `close`-having classes in the codebase.

#### Proposed fix

Either rename the method to reflect what it actually does, or expand the docstring:

**Option A** (rename; small API surface change):
```crystal
# Resets the read buffer. Does not close the underlying fd —
# fd ownership belongs to `TTY`, owned by `Terminal`.
def reset_buffer : Nil
  @buffer_pos = 0
  @buffer_len = 0
end
```

**Option B** (keep `close`, expand docstring):
```crystal
# Releases Reader state. **Does not close the file descriptor.**
#
# The fd is owned by `Termisu::TTY`, which in turn is owned by
# `Termisu::Terminal`. Closing the fd at this layer would break
# that ownership chain and leave `TTY` with a dangling fd.
#
# To fully release input resources, close the containing `Terminal`
# (typically via `Termisu#close`).
def close : Nil
  # ...
end
```

Prefer Option B — less churn, clearer intent. If `close` does no cleanup beyond resetting the buffer, consider deleting it and letting buffer state drop with the Reader instance.

#### Verification notes

Not re-verified. Read `reader.cr:240-244` before fixing.

---

### <a id="termisu-038"></a>TERMISU-038 — No runtime verification of `LibC::Winsize` struct size

**Severity:** LOW  •  **Status:** NEEDS-REPRO  •  **Component:** `[io]`
**Files:** `src/termisu/terminal/backend.cr:181-204` (per security review)

#### Description

Termisu defines a fallback `LibC::Winsize` struct when the stdlib doesn't provide one. There is no compile-time or runtime assertion that `sizeof(LibC::Winsize)` matches the kernel's expectation (8 bytes on every known platform). If Termisu is compiled on one kernel and run on a mismatched one (unlikely but possible in cross-compilation scenarios), `ioctl TIOCGWINSZ` could corrupt stack memory.

Termios has a similar guard (per llms.txt §2.2, compile-time size check) but Winsize doesn't.

#### Impact

Very low in practice — Winsize layout has been stable across Linux/BSD/Darwin for decades. Flagged only for defense-in-depth parity with the existing Termios guard.

#### Proposed fix

Compile-time check mirroring the Termios pattern:

```crystal
{% if LibC::Winsize.size != 8 %}
  {% raise "LibC::Winsize struct size mismatch: expected 8 bytes, got #{LibC::Winsize.size}. Termisu assumes standard POSIX layout." %}
{% end %}
```

Place next to the existing size check in `termios.cr`, or duplicate at each point of use.

#### Verification notes

Not re-verified. Read `terminal/backend.cr:181-204` and the Termios size-check to confirm the existing pattern before adding the Winsize equivalent.

---

### <a id="termisu-039"></a>TERMISU-039 — `apply_attribute_change` drops attributes retained across a batch reset

**Severity:** HIGH  •  **Status:** VERIFIED (differential-fuzz repro, 2026-07-20)  •  **Component:** `[rendering]`
**Files:** `src/termisu/render_state.cr:77-107`

#### Verified source

```crystal
# render_state.cr:77-90
private def apply_attribute_change(renderer : Renderer, new_attr : Attribute)
  reset_if_removing_attrs(renderer, new_attr)
  apply_new_attributes(renderer, new_attr)
  @attr = new_attr
end

private def reset_if_removing_attrs(renderer : Renderer, new_attr : Attribute)
  if (@attr & ~new_attr) != Attribute::None
    renderer.reset_attributes
    @fg = nil # Reset clears colors too
    @bg = nil
  end
end

# render_state.cr:105-107
private def needs_attr?(new_attr : Attribute, flag : Attribute) : Bool
  new_attr.includes?(flag) && !@attr.includes?(flag)
end
```

#### Description

When a style transition removes any attribute, `reset_if_removing_attrs` emits `reset_attributes` — which clears **every** attribute on the terminal. `apply_new_attributes` then re-enables only flags absent from the *old* `@attr` (`needs_attr?` checks `!@attr.includes?(flag)`), so attributes present in both the old and new state are never re-emitted. Colors survive because the reset branch nils `@fg`/`@bg`, forcing re-emission; the retained attributes get no equivalent treatment.

**Repro:** a batch transition `Bold|Underline → Bold` emits `reset_attributes` + colors but no `enable_bold`, leaving the cell visibly non-bold until its content next changes.

Found via differential fuzzing (random buffer ops diffed against a naive full-repaint model; failing seeds 42, 1337, 999983, 7). Byte-identical failures reproduce with the pre-change `buffer.cr` + `cell.cr` from HEAD, confirming the bug predates the damage-range work and is confined to `render_state.cr`.

#### Impact

Any UI that batches styled cells where consecutive runs share some attributes while dropping others renders the shared attributes incorrectly (e.g., syntax highlighting where a bold-underlined token is followed by a bold token). The glitch persists until the affected cell's content changes.

#### Proposed fix

After emitting `reset_attributes`, treat the tracked attribute state as `None` *before* computing what to enable:

```crystal
private def apply_attribute_change(renderer : Renderer, new_attr : Attribute)
  if (@attr & ~new_attr) != Attribute::None
    renderer.reset_attributes
    @fg = nil
    @bg = nil
    @attr = Attribute::None # terminal is attribute-free now; re-enable all of new_attr
  end
  apply_new_attributes(renderer, new_attr)
  @attr = new_attr
end
```

#### Related

**TERMISU-004** — `RenderState#reset` sets `@attr = Attribute::None`, a concrete value (unlike the `nil` sentinels used for `fg`/`bg`), so an `attr: None` batch right after `sync`/`invalidate` cannot clear stale terminal attributes either. The two bugs share a fix surface; adopting TERMISU-004's `Attribute?` nil-sentinel option covers both.

---

## Cross-cutting patterns

Three issues above recurrently surface the same structural theme and should be bundled for refactor:

- **TERMISU-003** (double SGR state)
- **TERMISU-007** (Renderer interface width)
- **TERMISU-011** (batch/cell allocations)
- **TERMISU-020** (apply_attribute_change efficiency)
- **TERMISU-025** (Cell occupancy coupling)

All five converge on the same code paths: Buffer → RenderState → Renderer → Terminal. The single high-leverage refactor is introduce a `Style` value type, narrow Renderer to 6 methods (`apply_style`, `write`, `move_cursor`, `set_cursor_visible`, `flush`, `size`, `close`), make RenderState the sole SGR optimizer (removing Terminal's cached setters), and switch Buffer storage to an explicit `Slot` enum (decoupling occupancy from Cell). This cluster represents roughly 2-3 weeks of focused work and resolves 5 tickets.

Similar coupling exists between **TERMISU-008** (facade bloat) and **TERMISU-021** (ffi/core.cr bloat) — both should be refactored together because they mirror each other structurally.

And the **backpressure** story (TERMISU-009 + TERMISU-023) wants a formal per-source policy contract, which also touches TERMISU-027 (Source template method).

## Suggested fix order

1. **Week 1 (correctness patches):** TERMISU-001, TERMISU-002, TERMISU-004, TERMISU-005, TERMISU-006, TERMISU-010. All small, high-value, no architectural risk.
2. **Sprint 1 (rendering refactor bundle):** TERMISU-003 + TERMISU-007 + TERMISU-011 + TERMISU-020 + TERMISU-025. Introduce Style, narrow Renderer, unify cache.
3. **Sprint 2 (facade decomposition):** TERMISU-008 + TERMISU-021. Extract Session.
4. **Sprint 3 (backpressure formalism):** TERMISU-009 + TERMISU-023 + TERMISU-027.
5. **Opportunistic:** Remaining MEDIUMs and LOWs as touched by other work.

## Contributing to tickets

When closing a ticket, leave a short resolution note at the bottom of the ticket with:
- Commit SHA or PR link
- Any scope changes from the original fix
- Whether the fix requires a benchmark baseline to verify

Ticket IDs are permanent — renumber to `TERMISU-036+` for new additions rather than reusing closed IDs.
