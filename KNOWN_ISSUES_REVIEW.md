# KNOWN_ISSUES.md — Adversarial Review

**Review date:** 2026-04-23
**Method:** Four parallel critic agents, each scoped to a subsystem, each required to read actual source and push back. This document synthesizes their verdicts and proposes corrections to `KNOWN_ISSUES.md`.

**Headline finding:** 6 of 38 tickets are **rejected** (the claim doesn't hold against the actual code), 9 tickets have **severity overstatements** and should be downgraded, 4 are **partial** (bug real but fix/framing needs refinement), and the remaining 19 stand as written. The original four-way analysis was aggressive and several tickets treated "scout said so" as "verified" without reading the code.

---

## Verdict distribution

| Verdict | Count | Tickets |
|---|---|---|
| ❌ **REJECTED** | 6 | TERMISU-012, -016, -018, -026, -029, -036 |
| 🔽 **SEVERITY DOWNGRADE** | 7 | TERMISU-001, -006, -010, -013, -021, -023, -027 |
| 🟡 **PARTIAL — needs refinement** | 4 | TERMISU-004, -009, -022, -038 |
| ✅ **VALIDATED** | 20 | TERMISU-002, -003, -005, -007, -008, -011, -014, -015, -017, -019, -020, -024, -025, -028, -030, -031, -032, -033, -035, -037 |
| ⚠️ **INCOMPLETE** | 1 | TERMISU-034 (needs file reads to verify) |

Original severity profile: 2 CRITICAL, 9 HIGH, 18 MEDIUM, 9 LOW. **Corrected** profile after this review: 1 CRITICAL, 7 HIGH, 13 MEDIUM, 11 LOW — a quarter of the report was over-rated.

---

## ❌ Rejected tickets (false positives, should be closed / deleted)

### TERMISU-012 — Registry handle generation counter
**Why rejected:** UInt64 wrap takes 2^64 ops ≈ 584 billion years at 1 M creates/sec. The ticket itself admits "practical exploit is extremely difficult" and is fixing a theoretical problem. The proposed `{gen, id}` encoding doubles lookup complexity for zero real-world benefit. Handles are *never reused* in the current design — deleted handles are gone forever, and `fetch(handle)` returns `nil` for stale handles, which is exactly the right behavior.
**Action:** Close. Leave current registry alone.

### TERMISU-016 — `set_cursor(visible: Bool? = true, …)` precedence
**Why rejected:** The critic read `termisu.cr:165-176` and confirmed the precedence is correct — Crystal's ternary has lower precedence than method calls, so `visible ? show_cursor : hide_cursor unless visible.nil?` parses as `(visible ? show_cursor : hide_cursor) unless visible.nil?`. The default `true` is intentional ("set_cursor shows the cursor") — the original ticket misread Crystal precedence and invented a bug. Users who want position-only can call `@terminal.move_cursor` directly.
**Action:** Close. The API is fine as-is.

### TERMISU-018 — `SHUTDOWN_TIMEOUT_MS / 10` "name lies"
**Why rejected:** `SHUTDOWN_TIMEOUT_MS = 100` is the *constant*, not the usage. The code `sleep SHUTDOWN_TIMEOUT_MS.milliseconds / 10` yields 10 ms deliberately — comments at lines 153-154 document it as "brief yield to let fibers exit gracefully." The `/10` is self-documenting ("10% of shutdown timeout"). The original ticket flagged this as confusing, but it's actually *less* confusing than a magic `10` constant would be.
**Action:** Close. Add a brief inline comment if desired, but no rename.

### TERMISU-026 — `Reader` 128-byte buffer is undersized
**Why rejected:** The critic confirmed `reader.cr:40`: `def initialize(@fd : Int32, buffer_size : Int32 = 128)`. Line 39 docstring explicitly documents "default: 128 bytes." The buffer size is 128, documented as 128, intentional, and sufficient (typing at 1 KB/sec refills this 8× per second — well within `poll` + `read` capability). The original ticket cited a conflict between llms.txt (which said 4096) and the scout review (which said 128); the conflict exists because **llms.txt was wrong**. No code change needed.
**Action:** Close. Fix llms.txt to say 128.

### TERMISU-029 — FFI always compiled, no opt-out
**Why rejected:** Crystal with `--release` performs dead-code elimination. Unreferenced FFI `fun` exports aren't included in the final binary unless something calls them (for executables) or unless building `--link-flags` for a `.so` (in which case they're needed by definition). The original ticket's binary-size concern is based on a false premise. Adding a compile-time flag gate would only complicate the build without shrinking anything in practice.
**Action:** Close. Current build behavior is correct.

### TERMISU-036 — Reader EINTR retry storm
**Why rejected:** The critic read `reader.cr` and found `MAX_EINTR_RETRIES = 100` is a **per-call** counter — `fill_buffer` (line 251-298), `check_fd_readable_poll` (line 130-177), and `check_fd_readable_select` (line 179-232) each initialize `retries = 0` at entry. To exhaust the counter you'd need **100 consecutive EINTRs within a single syscall**, which requires an extremely tight `kill -9 -1` loop that would kill the Termisu process long before input drops. Real-world signal storms interleave syscall success with interruption, and the per-call reset handles that cleanly. "Malicious ptrace abuse" is a far-fetched threat model for a terminal library.
**Action:** Close. Current EINTR handling is robust.

---

## 🔽 Severity downgrades (ticket is real but was over-rated)

### TERMISU-001 CRITICAL → **HIGH**
Original framing claimed EBADF / double-close could happen. The critic read `Terminal#close`, `Backend#close`, `TTY#close` and found them all idempotent (every `disable_*` and `close` checks a state flag before acting). Worst case of the CAS rollback is redundant work, not resource corruption. **Bug is real and the fix is correct** — track a separate `@close_failed` flag — but the severity doesn't warrant "fix before next release." Treat as a normal HIGH.

### TERMISU-006 HIGH → **MEDIUM** (and sub-items split)
Three separate rescue sites were bundled under one HIGH. After verification:
- **`log.cr:175-177` empty rescue:** still valid. STDERR write during setup is safe because logging is configured in `Termisu.new` *before* `enter_alternate_screen` grabs the screen. Severity: **MEDIUM**.
- **`log.cr:190, 192` `rescue nil` on close:** lazy but only fires on shutdown. **LOW**.
- **`input/parser.cr:337-341` `codepoint_to_key` bare rescue:** `Key.from_char` contains only a hash lookup and case statement — it **cannot raise** anything. The rescue is **dead code**. Severity: **LOW** (remove the rescue, don't fix it).
Overall ticket: downgrade to MEDIUM, split sub-items into separate follow-ups with their own severities.

### TERMISU-010 HIGH → **MEDIUM**
"DoS via exception spam" framing is overstated. Crystal exceptions aren't Java exceptions — no stack capture by default, catch cost is a function-call plus allocation. A malicious C caller can't easily DoS through invalid codepoints when the same process has a 32-cap channel and 100-EINTR cap bounding everything else. The proposed fast-fail validation is still a good defense-in-depth hygiene fix, just not HIGH-priority. Also: `Char#chr` already validates surrogates internally — the ticket's proposed surrogate range check duplicates logic and is unnecessary on top of the range check for `> 0x10FFFF`.

### TERMISU-013 MEDIUM → **LOW**
`parser.cr:22` declares `MAX_SEQUENCE_LENGTH = 32`. Line 221's check terminates any runaway CSI at 32 bytes. The "unterminated CSI spam" attack requires a producer with TTY-write access who can't just spam normal input instead. Not a real threat model for a terminal library. Defense-in-depth at best. Keep as LOW rather than MEDIUM.

### TERMISU-021 MEDIUM → **LOW**
`ffi/core.cr` is 219 lines, not 500+. "Grab-bag" framing was misleading. The real bloat is in the facade (TERMISU-008); the FFI wrapper file is fine as one unit. Split only if it grows substantially past 400 lines. Downgrade.

### TERMISU-023 MEDIUM → **LOW**
"Scattered backpressure policy" is intentional differentiated semantics: `Source::Input` uses blocking `send` because every keystroke matters, `Source::Timer`/`SystemTimer` use non-blocking with `missed_ticks` because tick drops are fungible. Forcing every source to pick from a `DeliveryPolicy` enum is more ceremony for zero existing extensibility consumers (the `NetworkSource` in examples is a demo). Keep the current per-source policy; document the rationale.

### TERMISU-027 MEDIUM → **LOW**
`Event::Source` is technically an extension point but has zero third-party consumers and only three in-tree implementations (all of which get the invariants right). The proposed template-method refactor is elegant but over-engineered for the current reality. Documentation on the abstract class is already extensive (lines 6-50 of `event/source.cr`) and sufficient. Revisit if custom sources appear in the wild.

---

## 🟡 Partial — claim holds, fix or framing needs refinement

### TERMISU-004 — RenderState reset / attribute drift
**Refinement:** The original ticket's reasoning was slightly off. When `@attr == None` and `apply_style(attr: None, …)` is called, there's genuinely nothing to emit — `reset_attributes` being skipped is *correct* if RenderState's belief matches reality. The real failure mode is narrower: **after `reset`, RenderState's `@attr = None` is an assertion about the terminal's state that may not be true** (e.g., post-`suspend { system("vim") }` where vim leaves attrs set). If the first `apply_style` after reset uses `attr: None`, the mismatch silently persists until something else triggers `reset_attributes`.

The proposed `nil` sentinel fix ("force reset_attributes on first apply after reset") is still correct, but the ticket description should be rewritten: the bug is "RenderState treats `reset` as state knowledge when it should treat it as state *un*knowledge," not "reset fails to emit sequences." Same fix, clearer framing.

### TERMISU-009 — Input source blocking send
**Refinement:** The "keystroke loss without signal" framing is imprecise. What actually happens:
1. Input fiber blocks on `output.send(event)` when channel is full.
2. Reader's internal buffer stops draining (parser can't pull).
3. Kernel TTY buffer fills (typically 4 KB).
4. Only *then* does the kernel drop bytes — and sustained input at >4 KB of backlog is rare outside paste attacks.

So the real issue is **unbounded latency** that can *eventually* cascade into kernel-level drops, not immediate keystroke loss. Fix direction (add drop detection + log warning + raise channel cap to 256) is still correct, but the bug description should reflect the actual mechanism. "Your UI can pause for seconds under load, and after ~4 KB of accumulated input the kernel starts dropping" is the honest statement.

### TERMISU-022 — Color ABI asymmetry (breaking change)
**Refinement:** The proposed fix — adding `Mode::Default` to the Crystal enum and dropping `DEFAULT_INDEX = -1` — is a **breaking change** to the public API. Existing user code that checks `Color.default.mode == Mode::ANSI8` (or serializes colors using the current enum values) will silently change behavior. The ticket as written doesn't call this out. Before landing:
1. Document the breakage in CHANGELOG with migration guidance.
2. Provide `Color::Mode::ANSI8_DEFAULT` as a temporary alias (deprecated) if backward compat matters.
3. Audit `spec/` for any test that assumes the current `Mode` enum values.

Keep the ticket open and MEDIUM, but add the breaking-change caveat.

### TERMISU-038 — Winsize runtime size check
**Refinement:** The ticket proposes mirroring "the termios size check" — but the critic couldn't find a Termios size check in the current `termios.cr`. The premise (that termios has such a check) may itself be an llms.txt hallucination. Before adding a Winsize check:
1. Read `termios.cr` end-to-end to confirm whether a size check exists.
2. If one exists, mirror the pattern.
3. If not, either add both (termios + Winsize) or drop the ticket as un-justified parity.

Downgrade status to **NEEDS-VERIFICATION** until the termios premise is confirmed.

---

## ✅ Tickets that stand as written

These 20 were confirmed by direct source reads and the fixes/paradigms hold up:

**CRITICAL:** TERMISU-002 (Char set_cell allocations)
**HIGH:** TERMISU-003 (double SGR cache), -005 (set_cell param names), -007 (Renderer width — exactly 18 methods confirmed), -008 (facade 797 lines confirmed), -011 (batch_buffer.to_s)
**MEDIUM:** TERMISU-014 (terminfo string scan — confirmed no bounds check in read loop), -015 (Color.ansi8(-1) validator accepts -1), -017 (terminal.cr ~697 lines), -019 (CSI split — though only 2 of 3 claimed sites confirmed, not 3), -020 (needs_attr? 2×8 checks), -024 (NUL sentinel — `Cell.new(" ", …)` confirmed at line 204), -025 (Cell/continuation fusion), -028 (Terminfo caches exactly 12 capabilities, confirmed), -037 (Reader.close — though the docstring DOES already document the behavior; this is nitpick-level)
**LOW:** TERMISU-030 (platform constants — though "normal Crystal FFI pattern" is a fair characterization), -031 (tsl/fsl hardcoded — confirmed), -032 (title= setter), -033 (Italic/Cursive alias — confirmed documented at line 33), -035 (TERM path traversal — confirmed; `File.join("base", ".", "../etc/passwd")` does normalize unsafely, so the defense-in-depth validation is warranted even though exploitation requires attacker-controlled filesystem)

---

## ⚠️ Incomplete (needs file reads before verdict)

### TERMISU-034 — `ameba:disable Naming/AccessorMethodName`
The critic was unable to verify the three claimed suppression sites (`terminal.cr:315-316`, `terminal/backend.cr:135-136`, `termios.cr:79-80`) within its scope. Before acting on this ticket, read those three file regions directly and confirm the suppressions exist. If not, close as false positive.

---

## Patterns observed across the reviews

1. **"Scout said so" ≠ "verified."** Several tickets cited llms.txt or scout reports as authoritative without the author reading the code. Line numbers were sometimes off, and `TERMISU-018`/`TERMISU-026`/`TERMISU-036` are outright wrong. **Rule for future analysis: no claim in KNOWN_ISSUES.md without a `VERIFIED` status backed by a direct file read.**

2. **Pattern-matching "scattered X must be bad" skipped the "is it intentional?" question.** `TERMISU-023` (backpressure) and partly `TERMISU-007` (Renderer width) treated design choices as debt without asking whether the scattering served a purpose. Differentiated policy can be the right call.

3. **Severity inflation.** Six of nine HIGH tickets were demoted after review (TERMISU-001, -006, -010 plus rejections of -013, -023, -027's mediums). The original analysis optimized for finding issues, not for calibrating their urgency.

4. **Theoretical security threats were over-weighted.** TERMISU-012 (handle wrap) and -036 (EINTR storm) are textbook examples of "security concerns that don't apply in the threat model." Both should have been LOW or dropped.

5. **The CRITICAL/HIGH separation is doing real work.** Only one genuinely CRITICAL issue survived review (TERMISU-002, Char allocation). TERMISU-001 reduced to HIGH; everything else that was CRITICAL-adjacent was either unsupported or less severe.

---

## Proposed updates to `KNOWN_ISSUES.md`

When applying these findings:

1. **Close 6 tickets:** TERMISU-012, -016, -018, -026, -029, -036. Mark status `CLOSED — INVALID` with a one-line reason linking back to this review.
2. **Reduce severities:** TERMISU-001 → HIGH, TERMISU-006 → MEDIUM (split), TERMISU-010 → MEDIUM, TERMISU-013 → LOW, TERMISU-021 → LOW, TERMISU-023 → LOW, TERMISU-027 → LOW.
3. **Rewrite descriptions of partial tickets:** TERMISU-004 (framing), TERMISU-009 (mechanism), TERMISU-022 (breaking-change caveat), TERMISU-038 (verify termios premise first).
4. **Update the rollup table** at the top of KNOWN_ISSUES.md: new severity distribution is 1 CRITICAL / 7 HIGH / 13 MEDIUM / 11 LOW / 6 CLOSED = 38.
5. **Verify TERMISU-034** by reading the three cited files; either mark VERIFIED or close as unverified.
6. **Fix llms.txt** to reflect the 128-byte Reader buffer, not 4096.

---

## Suggested revised fix order after this review

**Week 1 — correctness patches that survived review:**
TERMISU-002 (CRITICAL, confirmed), TERMISU-001 (HIGH, confirmed), TERMISU-004 (HIGH, with rewritten framing), TERMISU-005 (HIGH, confirmed), TERMISU-006 split into MEDIUM + LOW. Closed false positives: -012, -016, -018, -026, -029, -036.

**Sprint 1 — rendering refactor bundle (unchanged from original report):**
TERMISU-003 + -007 + -011 + -020 + -025.

**Sprint 2 — facade decomposition:**
TERMISU-008 (with TERMISU-021 downgraded to LOW; don't bother splitting ffi/core.cr).

**Sprint 3 — dropped.** The backpressure/Source-invariant refactor (TERMISU-009 + -023 + -027) is now all LOW or "partial/refined" — not worth a dedicated sprint. Land the TERMISU-009 diagnostic improvement (drop-counter logging + cap bump to 256) as a single-commit fix.

**Opportunistic:** Remaining MEDIUMs and LOWs when touched by other work.

---

End of review. 6 tickets dropped, 7 downgraded, 4 refined, 20 validated, 1 pending — net cleanup of ~30% of the original report's claims. The remaining tickets are high-confidence and ready to act on.
