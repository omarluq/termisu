# Termisu - Crystal TUI Library

## What This Is

A pure Crystal library for writing text-based user interfaces. Zero runtime dependencies. Provides cell-based rendering with double buffering, async event multiplexing, and full terminal capability handling. Inspired by termbox/termbox-go with a minimal, focused API.

**This is the author's project** - we're collaborating on ongoing development.

## Core Value

**Reliable TUI foundation** - Users can build terminal UIs with confidence: the library handles the terminal complexities (input, rendering, events) correctly and efficiently.

## Requirements

### Validated

*(See .planning/codebase/ARCHITECTURE.md for complete system overview)*
*(See TODO.md for detailed priority tracking)*

**Terminal Control** — Raw mode, alternate screen, state caching, EINTR handling, DEC private mode 2026 (synchronized updates)
**Rendering** — Double-buffered cell grid, diff rendering, RenderState optimization
**Input** — 170+ keys, modifiers, CSI/SS3/Kitty protocols, mouse (SGR + normal)
**Events** — Event::Loop multiplexer, Input/Resize/Timer sources, custom source API
**Colors** — ANSI-8, 256, RGB with conversions
**Attributes** — Bold, Dim, Italic, Underline, Blink, Reverse, Hidden, Strikethrough
**Terminfo** — Binary parser, 414 capabilities, full tparm processor
**Quality** — 979 tests, ameba clean, structured logging

### Active

**Immediate Focus Areas:**
- [ ] **Unicode/wide characters (P4.2)** — CJK/emoji support with wcwidth
- [ ] **Bracket paste mode (P4.5)** — Mode 2004 support
- [ ] **Focus tracking (P4.6)** — Mode 1004 support
- [ ] **Documentation** — Getting started guide, more examples
- [ ] **Integration tests** — PTY-based E2E testing

**Advanced Features (P5.x):**
- [ ] Scroll regions, ACS box drawing, OSC 8 hyperlinks
- [ ] Extended underline styles, image protocols (Kitty/Sixel)

### Out of Scope

- **Windows support** — Requires ConPTY (future consideration)
- **Widget system** — Keep library minimal, let users build on top
- **Runtime dependencies** — Zero deps is a core principle

## Context

**Author:** omarluq
**Version:** 0.0.2 (Alpha) → heading toward 0.1.0/1.0
**Status:** Production-ready core, gaps in Unicode and advanced features

**Design Philosophy:**
- Minimal API, small surface area
- Fiber-based async (Crystal's strength)
- Cell-based double buffering
- Terminfo-driven with builtin fallbacks

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Event::Any union type | Type-safe pattern matching | ✓ Good |
| Zero runtime deps | Easy sharding, no conflicts | ✓ Good |
| Structs for value types | Stack-allocated Color/Cell/RenderState | ✓ Good |
| Kernel timer support | Sub-millisecond precision for 60+ FPS | ✓ Good |

---
*Last updated: 2025-01-26 after initialization (author onboarding)*
