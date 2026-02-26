# Phase 04: Unicode Width and Mode Change Consistency

This phase fixes the two remaining bugs: the Unicode supplementary width overclassification (BUG-012) and the ModeChange#changed? contradiction (BUG-004). BUG-012 is the more complex one — it requires replacing the broad `0x1F780..0x1FAFF` width rule with precise ranges derived from Unicode data. BUG-004 is a straightforward doc/code alignment. After this phase, neutral non-emoji codepoints will correctly return width 1, and ModeChange#changed? behavior will match its documentation.

## Tasks

- [x] **BUG-004: Align ModeChange#changed? with its documentation.** In `src/termisu/event/mode_change.cr` at line ~45, the docs for `changed?` state it should return `false` when "Previous mode is nil (first change)". However, the implementation at line ~50 returns `true` if `prev.nil?`. Decide on the correct contract and align both code and docs:
  - The doc says first transition should return `false` (no change from "nothing")
  - The current code returns `true` for first transition
  - Consider which makes more sense for API users: is the first mode assignment a "change" or not?
  - Consensus: if you're setting a mode for the first time, that's not really a "change" from previous state — it's an initialization. Returning `false` makes sense.
  - Change the code to return `false` when `prev.nil?` instead of `true`
  - Update the comment if needed to reflect this clearly
  - Verify any specs for `ModeChange#changed?` still pass (or update them to match the corrected behavior)
  - **Done:** Changed `return true if prev.nil?` → `return false if prev.nil?` in `mode_change.cr:50`. Updated doc comment for clarity. Created `spec/termisu/event/mode_change_spec.cr` with 15 specs covering `changed?`, `to_raw?`, `from_raw?`, `to_user_interactive?`, `from_user_interactive?`. All pass.

- [x] **BUG-012: Fix Unicode supplementary width overclassification.** In `src/termisu/unicode_width.cr` at line ~718, the `wide_supplementary?` method uses the broad range `0x1F780..0x1FAFF` to mark codepoints as width 2. This includes many neutral (East Asian Width = N) non-emoji codepoints that should be width 1. Examples incorrectly classified as wide: `0x1F780`, `0x1F7D9`, `0x1F900`. Fix by:
  - Replace the broad `0x1F780..0x1FAFF` rule with explicit narrow/wide subranges based on Unicode Emoji property data
  - Codepoints that ARE emoji (have Emoji property) should be width 2
  - Codepoints that are neutral (EAW = N) and NOT emoji should be width 1
  - The specific subranges to fix:
    - `0x1F780..0x1F7FF` — Oracular/Sicillian/Lepontic/Linear Ideographs etc. — mostly NOT emoji, should be width 1
    - `0x1F800..0x1F8FF` — These are actually emoji (some transport symbols, etc.) — keep width 2
    - `0x1F900..0x1F9FF` — Supplemental Symbols and Pictographs — mixture, need careful subdivision
    - `0x1FA00..0x1FA6F` — Chess symbols, etc. — mostly NOT emoji, should be width 1
    - `0x1FA70..0x1FAFF` — Symbols and Pictographs Extended-A — mixture, need subdivision
  - The safest approach: explicitly list the wide ranges and treat everything else in the broad range as narrow:
    - Keep wide: `0x1F800..0x1F8FF`, actual emoji ranges like `0x1F900..0x1F9FF` may need subdivision but many ARE emoji
    - For precision, consult the Unicode Emoji data files which mark exactly which codepoints have Emoji=Yes
  - For this fix, break `0x1F780..0x1FAFF` into specific explicit ranges that are known to be wide/emoji, and don't include the neutral ones
  - A reasonable approximation that fixes the known-bad cases:
    - Remove `0x1F780..0x1FAFF` as a whole
    - Add back specific subranges that ARE emoji: `0x1F900..0x1F9FF` has many emojis but `0x1F930..0x1F9FF` are definitely emoji (people, etc.), the lower part `0x1F900..0x1F92F` is Supplemental Symbols and Pictographs — verify each subrange
  - Since this requires accurate Unicode data, the safest fix is to be more conservative: remove the over-broad range and add back only the definitively-known emoji subranges, even if we miss some less-common ones. Better to under-classify as narrow than over-classify neutral symbols as wide.
  - **Done:** Replaced broad `0x1F780..0x1FAFF` with precise subranges: `0x1F7E0..0x1F7EB` (colored shapes), `0x1F7F0` (heavy equals), `0x1F90C..0x1F9FF` (supplemental emoji, excluding non-emoji 1F900-1F90B), `0x1FA70..0x1FAFF` (Extended-A). Excluded Geometric Shapes Extended non-emoji (1F780-1F7DF), Supplemental Arrows-C (1F800-1F8FF), and Chess Symbols (1FA00-1FA6F). Added 17 new test assertions covering both the fixed neutral codepoints (width 1) and preserved emoji codepoints (width 2). All 1097 specs pass, ameba clean.

- [x] **Run `bin/hace spec` and `bin/hace ameba` to verify all changes pass.** After fixing Unicode width, test with the specific codepoints mentioned in the bug report (0x1F780, 0x1F7D9, 0x1F900) to confirm they now return width 1.
  - **Done:** All 1097 specs pass (0 failures). Ameba linter clean (0 failures). Specific bug report codepoints verified: `0x1F780` → width 1 ✓, `0x1F7D9` → width 1 ✓, `0x1F900` → width 1 ✓.
