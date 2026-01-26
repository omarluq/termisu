# INSPIRATION.md - Termbox Heritage

## Original Termbox (nsf/termbox - C)

**Status:** No longer maintained (author recommends forks or alternatives)

### Core Design Philosophy

> "The main idea is viewing terminals as a table of fixed-size cells and input being a stream of structured messages. Would be fair to say that the model is inspired by windows console API."

### The 12-Function API

Termbox's interface was intentionally minimal:

```c
tb_init()              // initialization
tb_shutdown()          // shutdown

tb_width()             // width of terminal screen
tb_height()            // height of terminal screen

tb_clear()             // clear buffer
tb_present()           // sync internal buffer with terminal

tb_put_cell()          // draw cell
tb_change_cell()       // modify cell
tb_blit()              // batch draw

tb_select_input_mode() // change input mode
tb_peek_event()        // peek a keyboard event
tb_poll_event()        // wait for a keyboard event
```

### Known Limitations (Author Acknowledged)

1. **Copy & paste** - "The notion of cells is not really compatible with the idea of text"
2. **Wide characters (CJK)** - "CJK runes often require more than one cell to display them nicely"

Despite these flaws, the author embraced KISS: "using such a simple model brings benefits in a form of simplicity."

### Target Use Case

> "At this point one should realize, that CLI (command-line interfaces) aren't really a thing termbox is aimed at. But rather pseudo-graphical user interfaces."

### Key Features (v1.1.0)

- Terminfo database parser with fallback built-in database
- 256-color and grayscale color modes
- Mouse event handling (ported from termbox-go)
- `tb_cell_buffer()` for direct back buffer access
- Output mode switching

---

## Termbox-Go (nsf/termbox-go)

**Status:** "Somewhat not maintained anymore" but author notes it moved people away from "ncurses mindset"

### Design Philosophy

> "The basic idea is an abstraction of the greatest common subset of features available on all major terminals and other terminal-like APIs in a minimalistic fashion. Small API means it is easy to implement, test, maintain and learn it."

### Cross-Platform Approach

- *nix: Terminal-based implementations
- Windows: WinAPI console based implementation
- **Goal:** Greatest common subset of features across platforms

### Notable Projects Using Termbox-Go

- **godit** - Emacsish text editor (author wrote this using termbox-go)
- **gotetris** - Tetris implementation
- **gocui** - Console UI library (built on termbox)
- **termui** - Terminal dashboard
- **termloop** - Terminal game engine
- **dry** - Docker container manager
- **cointop** - Cryptocurrency tracker

### Author's Recommendation

For new Go projects, author recommends:
- **gdamore/tcell** - More actively maintained
- **HTML-based UI** - For complicated interfaces/games

---

## Termisu's Relationship to Termbox

### Shared Principles

| Principle | Termbox | Termisu |
|-----------|---------|---------|
| Cell-based rendering | ✓ | ✓ |
| Minimal API | ✓ (12 functions) | ✓ (facade pattern) |
| Terminal as table | ✓ | ✓ |
| Input as event stream | ✓ | ✓ (Event::Any union) |
| Double buffering | ✓ | ✓ (explicit front/back) |
| Zero dependencies | ✓ | ✓ (pure Crystal) |

### Termisu Enhancements Beyond Termbox

| Feature | Termisu | Termbox |
|---------|---------|---------|
| Async event loop | ✓ (fibers + channels) | ✗ (blocking poll) |
| Custom event sources | ✓ (Event::Source API) | ✗ |
| Timer events | ✓ (sleep + kernel) | ✗ |
| Mode change events | ✓ | ✗ |
| Terminfo tparm | ✓ (full processor) | Partial |
| Enhanced keyboard | ✓ (Kitty protocol) | ✗ |
| System timer | ✓ (timerfd/kqueue) | ✗ |
| Type-safe events | ✓ (union types) | ✗ (C structs) |

### Design Divergences

| Aspect | Termbox Approach | Termisu Approach |
|--------|------------------|------------------|
| Language | C (manual memory) | Crystal (GC, structs) |
| Concurrency | None (single-threaded) | Fibers (async I/O) |
| Event system | Poll/peek only | Push-based channels |
| Color handling | Output modes | Color type with conversions |
| Platform abstraction | Build variants | Compile-time conditionals |

---

## API Comparison

### Initialization

```c
// Termbox (C)
tb_init();
// ... use library ...
tb_shutdown();
```

```go
// Termbox-Go
err := termbox.Init()
// ... use library ...
termbox.Close()
```

```crystal
// Termisu
termisu = Termisu.new
begin
  # ... use library ...
ensure
  termisu.close
end
```

### Rendering

```c
// Termbox
tb_clear();
tb_put_cell(x, y, &cell);
tb_present();
```

```go
// Termbox-Go
termbox.Clear()
termbox.SetCell(x, y, ch, fg, bg)
termbox.Flush()
```

```crystal
// Termisu
termisu.clear
termisu.set_cell(x, y, 'A', fg: Color.red, bg: Color.black)
termisu.render
```

### Events

```c
// Termbox
struct tb_event event;
tb_poll_event(&event);
switch (event.type) {
  case TB_EVENT_KEY: /* ... */
  case TB_EVENT_RESIZE: /* ... */
}
```

```go
// Termbox-Go
switch ev := termbox.PollEvent(); ev.Type {
case termbox.EventKey: /* ... */
case termbox.EventResize: /* ... */
}
```

```crystal
// Termisu
event = termisu.poll_event
case event
when Termisu::Event::Key    # keyboard
when Termisu::Event::Mouse  # mouse
when Termisu::Event::Resize # resize
when Termisu::Event::Tick   # timer (not in termbox!)
end
```

---

## Lessons From Termbox's Decline

### What Worked
- **Simplicity** - Small API enabled many language ports
- **Cross-platform** - Windows support via abstraction layer
- **Community** - Inspired ecosystem of TUI libraries

### What Didn't Work
- **Maintenance burden** - Author abandoned both C and Go versions
- **CJK support** - Never addressed wide characters properly
- **Copy-paste** - Cell model incompatible with text selection
- **Competition** - tcell, other libs offered more features

### Termisu's Response

1. **Maintenance** - Author-driven development with AI collaboration
2. **CJK** - Priority 4.2 (Unicode/wide characters) explicitly planned
3. **Copy-paste** - Bracket paste mode (P4.5) planned
4. **Features** - Async events, timers, custom sources ahead of termbox

---

## Ecosystem Influence

### Termbox Family Tree

```
nsf/termbox (C)
├── nsf/termbox-go (Go)
├── andrewsuzuki/termbox-crystal (Crystal) - *pre-Termisu*
├── Language bindings (Python, PHP, Rust, D, Swift, etc.)
└── Reimplementations (nimbox, ex_termbox, ...)

Termisu (Crystal)
├── Inspired by termbox philosophy
├── Enhanced with Crystal idioms (fibers, union types)
└── Zero dependency constraint (unlike some termbox forks)
```

### Modern Successors

| Library | Language | Status | Notes |
|---------|----------|--------|-------|
| tcell | Go | Active | Recommended by termbox-go author |
| bubbletea | Go | Active | Elm architecture, popular |
| Termisu | Crystal | Active | This project |
| termbox | C | Abandoned | Original |
| termbox-go | Go | Abandoned | Go implementation |

---

## Key Takeaways for Termisu Development

1. **Simplicity is strength** - Keep facade minimal, delegate complexity
2. **Acknowledge limitations** - Termisu documents CJK gap (P4.2)
3. **Community matters** - Good documentation and examples essential
4. **Async is differentiator** - Termisu's fiber-based event loop is unique
5. **Type safety** - Crystal union types superior to C void* casting
6. **Zero deps philosophy** - Worth maintaining, reduces distribution pain

---

*Last updated: 2025-01-26 - Understanding Termisu's termbox heritage*
