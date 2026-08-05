# Wide Character Support Plan for Termisu

**Status:** Research Complete | Implementation Pending

**Date:** 2025-02-24

## Quick Summary

Termisu currently has basic wide character support in `buffer.cr#char_display_width`, but it's incomplete. This plan documents the research on how major TUI libraries handle CJK characters, emoji, combining characters, and complex Unicode sequences.

## Current State

**What Termisu Does Now:**
- ✅ Has `char_display_width(ch : Char)` function in buffer.cr
- ✅ Covers ~60% of common CJK and emoji ranges
- ✅ Handles cursor advancement for wide chars in RenderState

**What's Missing:**
- ❌ Grapheme cluster support (combining characters like é = e + ´)
- ❌ ZWJ sequence handling (family emoji 👨‍👩‍👧‍👦)
- ❌ Skin tone modifier support
- ❌ Variation selector handling (VS15/VS16)
- ❌ Cell stores `Char` instead of full grapheme `String`
- ❌ No "continuation cell" marking for wide characters

## Key Findings

### 1. The Standard: wcwidth() and Unicode Annex #11

- **wcwidth()** returns: 0 (combining/control), 1 (narrow), 2 (wide), -1 (non-printable)
- **East Asian Width** categories: A (Ambiguous), F (Fullwidth), H (Halfwidth), N (Neutral), W (Wide)
- **Reference implementations:**
  - [Markus Kuhn's wcwidth.c](https://www.cl.cam.ac.uk/~mgk25/ucs/wcwidth.c)
  - [jquast/wcwidth](https://github.com/jquast/wcwidth) (Python, Unicode 15.1.0)
  - [termux/wcwidth](https://github.com/termux/wcwidth) (C, Unicode 15)

### 2. How Other Libraries Do It

| Library | Cell Storage | Width Calc | Combining | ZWJ |
|---------|--------------|------------|-----------|-----|
| **ratatui** | `String` (grapheme) + `skip: bool` | `unicode-width` crate | ✅ via `unicode-segmentation` | ⚠️ partial (width 2) |
| **tcell** | `main: rune` + `comb: []rune` | `golang.org/x/text/width` | ✅ explicit array | ⚠️ partial |
| **notcurses** | `gcluster: u32` or egcpool index | Custom wcwidth | ✅ full EGC | ✅ full support |
| **ncursesw** | `cchar_t` struct | libc wcwidth | ✅ wchar array | ⚠️ partial |

### 3. Crystal Has Built-in Grapheme Support

```crystal
# Crystal 1.19+ has String::Grapheme
string.each_grapheme do |grapheme|
  # grapheme is a String representing 1 user-perceived character
  # "e\u0301" => "é" (single grapheme, 2 codepoints)
end
```

## Recommended Implementation

### Design: "String-per-Cell with Skip Marker"

```crystal
struct Termisu::Cell
  property grapheme : String    # Full grapheme cluster (not just Char)
  property fg : Color
  property bg : Color
  property attr : Attribute
  property width : Int32         # Cached display width (0, 1, or 2)
  property skip : Bool = false  # Continuation cell marker
  
  def initialize(@grapheme = " ", @fg = Color.white, @bg = Color.default, @attr = Attribute::None)
    @width = UnicodeWidth.width(@grapheme)
  end
  
  # Backward compatibility
  def self.new(ch : Char, fg, bg, attr)
    new(ch.to_s, fg, bg, attr)
  end
end
```

### Why This Approach?

1. **Leverages Crystal's built-in grapheme support** - no external dependencies
2. **Simple API** - users work with strings naturally
3. **Future-proof** - handles new Unicode features automatically
4. **Backward compatible** - can keep `set_cell(x, y, ch, ...)` API

## Implementation Phases

### Phase 1: Core Infrastructure
- Create `UnicodeWidth` module with wcwidth algorithm
- Update `Cell` struct to store `grapheme: String`
- Add `width` and `skip` fields
- Implement backward-compatible `initialize(Char)` overload

### Phase 2: Buffer & Rendering
- Update `set_cell` to handle graphemes
- Add `set_grapheme` method for explicit grapheme setting
- Mark continuation cells when width > 1
- Update rendering to skip cells marked as continuation

### Phase 3: Advanced Features
- Proper combining character rendering
- ZWJ sequence width calculation
- Skin tone modifier support
- Variation selector (VS15/VS16) handling

### Phase 4: Testing
- Unit tests for width calculation
- Visual test suite for CJK, emoji, combining chars
- Terminal compatibility matrix

## Edge Cases to Handle

| Case | Example | Width | Notes |
|------|---------|-------|-------|
| CJK | '中', '日' | 2 | Most common case |
| Emoji | '😀', '👍' | 2 | Standard emoji |
| ZWJ | '👨‍👩‍👧‍👦' | 2 | 7 codepoints, 1 grapheme |
| Combining | "e\u0301" (é) | 1 | 2 codepoints, 1 grapheme |
| VS15 | "\u26A0\uFE0E" (⚠︎) | 1 | Text presentation |
| VS16 | "\u26A0\uFE0F" (⚠️) | 2 | Emoji presentation |
| Skin tone | "\u{1F44D}\u{1F3FB}" (👍🏻) | 2 | Base + modifier |

## Performance Considerations

- **Width caching:** Memoize codepoint widths to avoid repeated lookups
- **Table size:** Full Unicode 15 tables ~100KB; can use subset for common ranges
- **Grapheme iteration:** Slightly slower than char iteration, but acceptable for TUI

## References

Full research report: `.claude/cache/agents/oracle/output-widechar-*.md`

**Key Sources:**
- [UAX #11 - East Asian Width](https://www.unicode.org/reports/tr11/)
- [UAX #29 - Text Segmentation](https://www.unicode.org/reports/tr29/)
- [ratatui Issue #1438](https://github.com/ratatui/ratatui/discussions/1438)
- [tcell source](https://github.com/gdamore/tcell)
- [notcurses documentation](https://notcurses.com/notcurses_cell.3.html)

## Next Steps

1. Review and approve this plan
2. Create UnicodeWidth module
3. Update Cell struct
4. Implement grapheme-aware rendering
5. Add comprehensive tests
