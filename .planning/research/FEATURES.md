# FEATURES.md - TUI Library Feature Landscape (2025)

## Table Stakes Features (Expected in Any TUI Library)

These are features users expect when choosing a TUI library. Termisu has most of these.

| Feature | Status | Notes |
|---------|--------|-------|
| **Cell-based rendering** | ✅ | Double-buffered, diff-based |
| **Keyboard input** | ✅ | 170+ keys, modifier handling |
| **Mouse support** | ✅ | SGR + normal protocols |
| **Terminal resize handling** | ✅ | Event::Resize with sync |
| **ANSI colors** | ✅ | 8, 256, RGB modes |
| **Text attributes** | ✅ | Bold, dim, italic, underline, blink, reverse, hidden, strikethrough |
| **Alternate screen** | ✅ | terminfo enter_ca_seq/exit_ca_seq (smcup/rmcup, DECSET 1049) with restore |
| **Raw mode** | ✅ | Multiple modes (raw, cooked, cbreak, password, semi_raw) |
| **Event polling** | ✅ | Blocking, timeout, non-blocking, iterator |
| **Zero dependencies** | ✅ | Pure Crystal, no external deps |
| **Cross-platform** | ✅ | Linux, macOS, BSD (Windows future) |

## Differentiating Features (What Makes Termisu Unique)

### Async Event System (Priority 8 - Complete)

**Most TUI libraries:** Blocking poll/peek model (termbox style)

**Termisu:** Push-based async with fibers + channels

```crystal
# Built-in sources
termisu.enable_timer(16.milliseconds)           # Animation ticks
termisu.enable_system_timer(8.milliseconds)     # High-precision timer

# Custom sources
class CustomSource < Termisu::Event::Source
  def start(output : Channel(Termisu::Event::Any)) : Nil
    spawn do
      while running?
        output.send(MyCustomEvent.new)
        sleep 1.second
      end
    end
  end
end

termisu.add_event_source(CustomSource.new)
```

**Why this matters:**
- No busy-wait loops
- Multiple event types unified
- Custom sources extensible
- Graceful shutdown

### Kernel-Level Timer (Priority 8 - Complete)

| Timer Type | Precision | Max FPS | Missed Detection |
|------------|-----------|---------|------------------|
| Sleep-based (termbox) | ~1-2ms jitter | ~48 FPS | No |
| Kernel timerfd/kqueue | Sub-millisecond | ~90 FPS | Yes |

**Termisu advantage:** Actual 60 FPS for smooth animation

### Enhanced Keyboard (Kitty Protocol)

Distinguishes keys that traditional termbox can't:
- Tab vs Ctrl+I
- Enter vs Ctrl+M
- Escape vs Ctrl+[

### Terminfo Tparm Processor

Full parametrized string processor - most TUI libraries hardcode escape sequences:

```crystal
# Termisu can evaluate complex terminfo capabilities
cup = terminfo.get_string("cup")  # cursor position
evaluated = terminfo.tparm(cup, row, col)  # %d %d substitution
```

### Type-Safe Events (Crystal Union Types)

```crystal
alias Event::Any = Key | Mouse | Resize | Tick | ModeChange

# Compiler-checked pattern matching
case event
when Termisu::Event::Key
when Termisu::Event::Mouse
# Compile error if missing case!
end
```

## Competitive Feature Comparison

| Feature | Termisu | termbox (C) | termbox-go | bubbletea (Go) | tcell (Go) |
|---------|---------|-------------|------------|----------------|------------|
| Cell rendering | ✅ | ✅ | ✅ | ✅ | ✅ |
| Async events | ✅ | ❌ | ❌ | ✅ | ✅ |
| Custom sources | ✅ | ❌ | ❌ | ✅ | ✅ |
| Timer events | ✅ | ❌ | ❌ | ✅ | ✅ |
| Kernel timer | ✅ | ❌ | ❌ | ❌ | ❌ |
| Enhanced keyboard | ✅ | ❌ | ❌ | ❌ | ✅ |
| Unicode wide chars | 🟡 P4.2 | ❌ | ❌ | ✅ | ✅ |
| Bracket paste | 🟡 P4.5 | ❌ | ❌ | ✅ | ✅ |
| Focus tracking | 🟡 P4.6 | ❌ | ❌ | ❌ | ✅ |
| OSC 8 hyperlinks | 🟡 P5.x | ❌ | ❌ | ❌ | ✅ |
| Image protocols | 🟡 P5.x | ❌ | ❌ | ❌ | ✅ (Kitty) |
| Zero deps | ✅ | ✅ | ✅ | ❌ | ❌ |
| Windows support | ❌ | ✅* | ✅ | ✅ | ✅ |

*Termbox C has Windows fork, main repo nix-only*

## Feature Gaps (Prioritized)

### High Priority (P4.x)

| Feature | Priority | Est. Effort | Impact |
|---------|----------|-------------|--------|
| **Unicode/wide characters** | P4.2 | 4-6 hours | HIGH - CJK/emoji broken |
| **Bracket paste mode** | P4.5 | 2-3 hours | MEDIUM - UX issue |
| **Focus tracking** | P4.6 | 1-2 hours | LOW - Optimization |
| **Extended color detection** | P4.7 | 2-3 hours | LOW - Fallback works |

### Backlog (P5.x - Advanced Features)

| Feature | Description | Use Case |
|---------|-------------|----------|
| **Scroll regions** | DECSTBM, define scrollable area | Status bars, headers |
| **ACS box drawing** | Alternate char set | Traditional TUI borders |
| **OSC 8 hyperlinks** | Clickable URLs | Modern terminal UX |
| **Extended underline** | Double, curly, dotted | Styled text |
| **Kitty graphics** | Inline images | Rich content |
| **Sixel** | Bitmap graphics | Retro terminals |

## Modern Terminal Expectations (2025)

### What Users Expect Today

1. **Unicode support** - Non-negotiable for global users
2. **True color** - 24-bit RGB expected
3. **Mouse support** - Click, drag, scroll
4. **Copy-paste** - Bracketed paste essential
5. **Resize handling** - Graceful, no corruption
6. **Performance** - 60 FPS animation
7. **Accessibility** - Screen reader friendly (limited in terminals)

### Emerging Trends (Nice to Have)

- **Inline images** (Kitty, Sixel)
- **Clickable links** (OSC 8)
- **Bold/italic text** (extended SGR)
- **Underline styles** (curly, double, dotted)
- **True color emoji** - Requires wide char support

## Feature Implementation Status

### Complete (P1-P3, P8)

- ✅ Terminal control (raw, alternate screen, caching)
- ✅ Double-buffered rendering with diff optimization
- ✅ Input parsing (170+ keys, modifiers)
- ✅ Async event loop (Event::Source API)
- ✅ Timer sources (sleep + kernel)
- ✅ Color modes (ANSI-8, 256, RGB)
- ✅ Text attributes (8 SGR attributes)
- ✅ Terminfo parser (binary + tparm)
- ✅ Logging system (structured, async)
- ✅ Terminal mode switching (6 modes)
- ✅ Mode change events
- ✅ Enhanced keyboard (Kitty protocol)

### In Progress (P4.x)

- 🟡 Unicode/wide characters (wcwidth)
- 🟡 Bracket paste mode (2004)
- 🟡 Focus tracking (1004)
- 🟡 Extended color detection

### Planned (P5.x)

- 📋 Scroll regions
- 📋 ACS box drawing
- 📋 OSC 8 hyperlinks
- 📋 Extended underline styles
- 📋 Kitty graphics protocol
- 📋 Sixel bitmap support

### Out of Scope

- ❌ Windows support (requires ConPTY, future consideration)
- ❌ Widget system (keep library minimal)
- ❌ Layout engine (user space concern)
- ❌ Component library (separate repo)

## Feature Complexity Analysis

### Simple (1-3 hours)
- Bracket paste mode
- Focus tracking
- Extended color detection
- Terminal mode API

### Medium (4-8 hours)
- Unicode/wide characters
- Scroll regions
- ACS box drawing
- OSC 8 hyperlinks

### Complex (2-3 days)
- Kitty graphics protocol
- Sixel bitmap support
- Windows ConPTY backend
- Advanced layout engine (if ever)

## Sources

- [nsf/termbox](https://github.com/nsf/termbox) - Original C library
- [nsf/termbox-go](https://github.com/nsf/termbox-go) - Go implementation
- [gdamore/tcell](https://github.com/gdamore/tcell) - Modern Go alternative
- [charmbracelet/bubbletea](https://github.com/charmbracelet/bubbletea) - Elm-style TUI

---

*Last updated: 2025-01-26 - Feature landscape analysis for Termisu*
