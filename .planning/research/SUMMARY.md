# RESEARCH_SUMMARY.md - TUI Library Research Synthesis

## Research Context

**Goal:** Understand Termisu's position in the TUI library ecosystem by examining:
1. Original planning documents and TODOs
2. Inspiration sources (nsf/termbox, nsf/termbox-go)
3. Current feature landscape (2025)
4. Common pitfalls to avoid

## Key Findings

### 1. Termisu's Heritage

Termisu follows **nsf/termbox's philosophy** but enhances it with Crystal's strengths:

| Aspect | Termbox (C) | Termisu (Crystal) |
|--------|-------------|-------------------|
| API Size | 12 functions | Facade pattern |
| Event Model | Poll/peek only | Push-based async |
| Concurrency | None | Fibers + channels |
| Type Safety | C structs | Union types |
| Timer | None | Sleep + kernel |
| Custom Events | No | Event::Source API |

**nsf (original author)** on termbox's decline:
- "The library is no longer maintained"
- "I recommend gdamore/tcell for Go"
- Cell model incompatible with copy-paste and CJK

### 2. What Makes Termisu Unique

**Competitive Advantages:**
1. **Async event loop** - Push-based with fibers, not blocking poll
2. **Kernel timer** - Sub-millisecond precision, ~90 FPS achievable
3. **Custom event sources** - Extensible architecture
4. **Type-safe events** - Crystal union types vs C void* casting
5. **Zero dependencies** - Pure Crystal, easy sharding
6. **Terminfo tparm** - Full parametrized string processor

**No other TUI library combines:** async events + kernel timer + zero deps + type safety

### 3. Feature Status Matrix

| Feature Area | Status | Notes |
|--------------|--------|-------|
| **Core (P1-P3)** | ✅ Complete | Terminal control, rendering, input |
| **Events (P8)** | ✅ Complete | Async loop, custom sources, timers |
| **Colors** | ✅ Complete | ANSI-8, 256, RGB with conversions |
| **Attributes** | ✅ Complete | 8 SGR attributes |
| **Terminfo** | ✅ Complete | Parser + tparm processor |
| **Unicode (P4.2)** | 🟡 Main Gap | CJK/emoji need wcwidth |
| **Bracket paste (P4.5)** | 🟡 Planned | Mode 2004 support |
| **Focus tracking (P4.6)** | 🟡 Planned | Mode 1004 support |
| **Advanced (P5.x)** | 📋 Backlog | Hyperlinks, images, scroll regions |

### 4. Priority Recommendations

**Highest Impact (P4.2):** Unicode/wide character support
- **Estimated:** 4-6 hours
- **Impact:** HIGH - CJK/emoji display incorrectly
- **User Expectation:** Non-negotiable in 2025

**Medium Impact (P4.5-P4.7):** Input enhancements
- Bracket paste, focus tracking, color detection
- **Estimated:** 5-8 hours combined
- **Impact:** MEDIUM - UX improvements

**Low Priority (P5.x):** Advanced features
- OSC 8 hyperlinks, image protocols, scroll regions
- **Impact:** LOW - Nice to have, not blocking

### 5. Competitive Position

**Versus termbox/termbox-go:**
- ✅ More modern async architecture
- ✅ Better type safety (Crystal vs C)
- ✅ Timer support (termbox has none)
- ✅ Active development
- ❌ No Windows support yet

**Versus bubbletea (Go):**
- ✅ Zero dependencies (bubbletea requires lipgloss, bubbles)
- ✅ Kernel timer precision
- ❌ Smaller ecosystem
- ❌ No widget system (by design)

**Versus tcell (Go):**
- ✅ Zero dependencies (tcell has many)
- ✅ Simpler API
- ❌ Fewer terminal features (Unicode, hyperlinks, images)

## Design Philosophy Alignment

### Termisu Adheres To:

✅ **KISS principle** - Small facade, delegation to components
✅ **Cell-based model** - Terminal as table of fixed-size cells
✅ **Input as events** - Structured message stream
✅ **Zero deps** - Pure Crystal, no external runtime deps
✅ **Type safety** - Compiler-checked unions, not runtime casting

### Termisu Improves Upon:

✅ **Termbox's async gap** - Fiber-based event loop
✅ **Termbox's timer gap** - Sleep + kernel timers
✅ **Termbox's type safety** - Crystal union types
✅ **Termbox's maintenance** - Author-driven + AI collaboration

### Termisu Acknowledges (Following nsf's Honesty):

🟡 **Cell model limits** - Copy-paste problematic, bracket paste helps
🟡 **CJK not first-class** - P4.2 planned to address
🟡 **Not for CLI** - Pseudo-GUI focus, not command-line tools

## Technical Debt Assessment

**Overall:** EXCELLENT (from CONCERNS.md)

| Category | Count | Severity |
|----------|-------|----------|
| Critical | 0 | None |
| High | 1 | Unicode support |
| Medium | 2 | Cleanup guarantee, bracket paste |
| Low | 3 | Validation, focus tracking, color detection |

**Code Quality:**
- 979 tests passing
- 1.26x test-to-code ratio
- Ameba clean (linting)
- No blocking issues

## Architecture Strengths

### Well-Designed Patterns

1. **Double buffering** - Diff-based rendering, minimal escape sequences
2. **Event sources** - Extensible abstract class
3. **State caching** - RenderState prevents redundant sequences
4. **EINTR handling** - Retry loops for robust I/O
5. **Platform abstraction** - Conditional compilation + fallbacks
6. **Value types** - Structs for Cell/Color (stack allocation)
7. **Logging** - Async file logging, structured

### Previously Fixed Issues

✅ Parser complexity - Split into 3 SRP methods
✅ String allocation - String.build for terminfo
✅ Magic numbers - ANSI8_THRESHOLD constant

## Roadmap Implications

### Phase 4: Input Enhancements (P4.x)

**P4.2 - Unicode/Wide Characters** (HIGH PRIORITY)
- Add wcwidth/wcswidth bindings or pure Crystal
- Track cell width (1 or 2 columns)
- Handle wide character cursor movement
- Test with CJK and emoji

**P4.5 - Bracket Paste Mode**
- Mode 2004 support
- Detect `\e[200~` (start) and `\e[201~` (end)
- Create Events::Paste struct

**P4.6 - Focus Tracking**
- Mode 1004 support
- Parse `\e[I` (focus) and `\e[O` (blur)

**P4.7 - Extended Color Detection**
- Check `COLORTERM` env var
- Query terminal capabilities (DA1/DA2)
- Add `Color.supports_truecolor?` method

### Phase 5: Advanced Features (P5.x) - Backlog

Lower priority, nice-to-have:
- Scroll regions
- ACS box drawing
- OSC 8 hyperlinks
- Extended underline styles
- Kitty graphics protocol
- Sixel bitmap support

## Success Criteria Definition

### v0.1.0 Milestone (Library Complete)

- [ ] P4.2: Unicode/wide characters (MAIN GAP)
- [ ] P4.5: Bracket paste mode
- [ ] Documentation: Getting started guide
- [ ] Examples: More demos

### v1.0.0 Milestone (Production Ready)

- [ ] All P4.x complete
- [ ] E2E tests with PTY framework
- [ ] Performance benchmarks at 60 FPS
- [ ] Comprehensive API documentation

## Recommended Next Steps

1. **Implement P4.2 (Unicode)** - Highest user impact
2. **Add E2E tests** - PTY-based integration testing
3. **Improve docs** - Getting started guide for new users
4. **Consider P4.5-P4.7** - Input polish based on user feedback

## Sources

- [nsf/termbox](https://github.com/nsf/termbox) - Original C library (no longer maintained)
- [nsf/termbox-go](https://github.com/nsf/termbox-go) - Go implementation (not maintained)
- Termisu `TODO.md` - 807 lines of priority tracking
- Termisu `docs/ARCHITECTURE.md` - Design philosophy
- Termisu `.planning/codebase/` - 7 analysis documents

---

*Research completed: 2025-01-26*
*Ready for roadmap creation*
