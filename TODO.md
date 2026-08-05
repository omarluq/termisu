# Termisu Development TODO

## Project Status

**Version:** 0.0.2 (Alpha)
**Source Lines:** ~6,200 (47 files)
**Test Lines:** ~7,800 (38 spec files)
**Test-to-Code Ratio:** 1.26x
**Test Coverage:** 979 tests, 0 failures
**Linting:** 111 files, 0 issues (ameba clean)
**Priority 1:** ✅ All critical fixes complete
**Priority 2:** ✅ All performance optimizations complete
**Priority 3:** ✅ Input handling system complete (P3.1, P3.2, P3.3, P3.4)
**Priority 8:** ✅ Async event system complete (P8.1-P8.6)
**Task Runner:** hace (migrated from task-go)

---

## Current Architecture

```
Termisu (facade)
├── Terminal (I/O control, state caching, mouse/keyboard protocols)
│   ├── Termios (raw mode, ISIG disabled)
│   └── Renderer interface (abstract)
├── Terminfo (capabilities)
│   ├── Database (standard path search)
│   ├── Parser (binary format, 16/32-bit magic)
│   ├── Builtin (xterm/linux fallbacks)
│   ├── Capabilities (414 STRING_CAPS, O(1) lookup)
│   └── Tparm (full processor with conditionals, stack, variables)
├── Buffer (double-buffered cell grid)
│   ├── Cell (char, fg, bg, attr)
│   ├── Cursor (position, visibility, clamping)
│   ├── RenderState (escape sequence optimization)
│   └── IO::Memory batch buffer
├── Reader (buffered input, EINTR/EAGAIN handling, select timeouts)
├── Input (complete input system)
│   ├── Key (170+ keys: A-Z, a-z, 0-9, symbols, F1-F24, nav)
│   ├── Modifier (Shift, Alt, Ctrl, Meta flags)
│   ├── Parser (CSI, SS3, Kitty protocol, modifyOtherKeys)
│   └── Mouse (SGR mode 1006, normal mode 1000)
├── Event (async event system)
│   ├── Any (Key | Mouse | Resize | Tick | ModeChange union)
│   ├── Key (key + char + modifiers struct)
│   ├── Mouse (x, y, button, modifiers, motion)
│   ├── Resize (width, height, old dimensions)
│   ├── Tick (frame, elapsed, delta, missed_ticks)
│   ├── ModeChange (mode, previous_mode)
│   ├── Source (abstract class for event producers)
│   │   ├── Input (keyboard/mouse from TTY)
│   │   ├── Resize (SIGWINCH + polling)
│   │   ├── Timer (sleep-based interval ticks)
│   │   └── SystemTimer (kernel timerfd/kqueue ticks)
│   ├── Poller (kernel event polling abstraction)
│   │   ├── Epoll (Linux epoll + timerfd)
│   │   ├── Kqueue (macOS/BSD kqueue + EVFILT_TIMER)
│   │   └── Poll (POSIX poll fallback)
│   └── Loop (multiplexer coordinating all sources)
├── Color (multi-mode)
│   ├── Default, ANSI-8, ANSI-256, RGB/TrueColor
│   ├── Conversions (RGB ↔ ANSI-256 ↔ ANSI-8)
│   └── Palette (standard 256-color)
├── Attribute (Bold, Underline, Reverse, Blink, Dim, Cursive, Hidden, Strikethrough)
└── Logging (structured async/sync dispatch)
    ├── SafeFileIO (graceful shutdown)
    └── Component logs (Terminal, Buffer, Reader, Terminfo, Input, Event)
```

---

## Priority 1: Critical Fixes ✅ COMPLETE

### P1.1 - Fix Parser Error Handling ✅ COMPLETED
- ParseError class with typed errors (InvalidMagic, TruncatedData, InvalidHeader, InvalidOffset)
- Comprehensive validation for header, magic number, and offsets
- 15+ tests covering error handling edge cases

### P1.2 - Fix Cursor Bounds After Resize ✅ COMPLETED
- Cursor#clamp method called in Buffer#resize
- Bounds check in Buffer#set_cursor with clamping
- 13+ tests for cursor bounds scenarios

### P1.3 - Handle EINTR in Reader ✅ COMPLETED
- EINTR retry loops in check_fd_readable and fill_buffer
- MAX_EINTR_RETRIES limit, IOError class for context
- Handles EAGAIN, EBADF, EIO errors
- 32+ tests including pipe-based I/O tests

---

## Priority 2: Performance Optimizations ✅ COMPLETE

### P2.1 - Optimize Attribute Rendering ✅ COMPLETED
- RenderState struct tracks terminal state (fg, bg, attr, cursor position)
- render_row_diff and render_row_full with cell batching
- Only emits escape sequences when state changes
- 25+ tests for rendering optimization

### P2.2 - Add State Caching in Terminal ✅ COMPLETED
- Cached state: @cached_fg, @cached_bg, @cached_attr, @cached_cursor_visible
- Skip redundant escape sequences
- Reset integrated with screen operations
- 27 tests covering caching scenarios

---

## Priority 3: Feature Completion ✅ MOSTLY COMPLETE

### P3.1 - Mouse Input Support ✅ COMPLETED
- SGR extended mouse protocol (mode 1006) with full parsing
- Normal mouse protocol (mode 1000) support
- Mouse::Button enum with from_cb decoding (Left, Middle, Right, WheelUp, WheelDown, Release)
- Motion events with MOUSE_MOTION_BIT detection
- Modifier extraction from mouse events
- Terminal#enable_mouse / #disable_mouse sequences

### P3.2 - Event System & Key Sequence Parsing ✅ COMPLETED
- Complete Key enum with 170+ keys (A-Z, a-z, 0-9, all symbols, F1-F24, nav keys)
- Modifier flags (Shift, Alt, Ctrl, Meta) with from_xterm_code
- Input::Parser with timeout-based ESC detection (50ms)
- CSI sequence parsing (arrows, nav, function keys, tilde codes)
- SS3 sequence parsing (F1-F4, alternate arrows)
- Kitty keyboard protocol support (codepoint + modifiers)
- modifyOtherKeys support (CSI 27;modifier;keycode~)
- Linux console function keys (\e[[A through \e[[E)
- Alt+key and Ctrl+key detection
- Hash-based O(1) key lookups (CSI_KEYS, TILDE_KEYS, SS3_KEYS, KITTY_CODEPOINTS)
- Events::Key and Events::Mouse structs with convenience methods
- Termisu#poll_event, #wait_event integration

### P3.3 - Use Terminfo for Cursor Movement ✅ COMPLETED
- Full tparm processor (Processor, Conditional, Operations, Variables, Output)
- Terminfo `cup` capability for cursor positioning
- 12 cached parametrized capabilities (cup, setaf, setab, cuf, cub, cuu, cud, hpa, vpa, ech, il, dl)
- Comprehensive tparm tests

### P3.4 - Extended Attribute Support ✅ COMPLETED
- dim (SGR 2), sitm (SGR 3), invis (SGR 8) in REQUIRED_FUNCS
- Builtin fallbacks for xterm/linux
- Terminfo methods: dim_seq, italic_seq, hidden_seq
- Renderer interface: enable_dim, enable_cursive, enable_hidden
- Terminal implementation with caching
- RenderState applies new attributes during rendering
- 19 tests for extended attributes

---

## Priority 4: Missing Terminal Features

### P4.1 - SIGWINCH Resize Event Handling ✅ COMPLETED
**Status:** IMPLEMENTED via P8.1 (Async Architecture)
**Implementation:** Event::Source::Resize with SIGWINCH + polling hybrid
**API:** `Event::Resize` with `width`, `height`, `old_width`, `old_height`, `changed?`

### P4.2 - Unicode / Wide Character Support 🟡 MEDIUM PRIORITY
**Status:** NOT IMPLEMENTED
**Issue:** No handling for double-width characters (CJK, emoji)
**Impact:** CJK text and emoji display incorrectly (overlap or misalign)
**Action:**
- [ ] Add wcwidth/wcswidth bindings or implementation
- [ ] Track cell width in Buffer (1 or 2 columns)
- [ ] Handle wide character cursor movement
- [ ] Test with CJK characters and emoji

### P4.3 - Synchronized Updates (DEC mode 2026) ✅ COMPLETED
**Status:** IMPLEMENTED
**Implementation:**
- [x] Added BSU/ESU constants (`\e[?2026h` / `\e[?2026l`) to Terminal
- [x] Added `@sync_updates` flag (enabled by default)
- [x] Wrapped `render()` and `sync()` methods with BSU/ESU sequences
- [x] Added `sync_updates?` getter and `sync_updates=` setter
- [x] Added `sync_updates` constructor parameter to Terminal and Termisu
- [x] Unsupported terminals gracefully ignore the sequences (self-degrading)
- [x] 7 tests covering constants, flag defaults, and runtime toggling
**Design:** See `dec-plan.md` for design document

### P4.4 - Strikethrough Attribute (SGR 9) ✅ COMPLETED
**Status:** IMPLEMENTED
**Implementation:**
- [x] Added `Strikethrough = 128` to Attribute flags enum
- [x] Added `smxx` capability to REQUIRED_FUNCS (index 27)
- [x] Added `"\e[9m"` to Builtin fallbacks (xterm/linux)
- [x] Added `strikethrough_seq` method to Terminfo
- [x] Added `enable_strikethrough` to Renderer interface
- [x] Implemented in Terminal with caching
- [x] Updated RenderState to apply strikethrough
- [x] Added tests for attribute, render_state, and builtin specs
- [x] Updated examples (showcase.cr, simple.cr)
- [x] Updated README documentation

### P4.5 - Bracket Paste Mode 🟢 LOW PRIORITY
**Status:** NOT IMPLEMENTED
**Issue:** No bracketed paste support (mode 2004)
**Impact:** Paste operations may trigger unintended commands
**Action:**
- [ ] Add enable_bracketed_paste / disable_bracketed_paste
- [ ] Detect paste start (\e[200~) and end (\e[201~) sequences
- [ ] Create Events::Paste with pasted content
- [ ] Buffer paste content between brackets

### P4.6 - Focus Tracking (mode 1004) 🟢 LOW PRIORITY
**Status:** NOT IMPLEMENTED
**Issue:** Cannot detect terminal focus/blur events
**Impact:** Applications cannot optimize for background state
**Action:**
- [ ] Add enable_focus_tracking / disable_focus_tracking
- [ ] Parse focus events (\e[I for focus, \e[O for blur)
- [ ] Create Events::Focus(gained: Bool) struct

### P4.7 - Extended Color Detection 🟢 LOW PRIORITY
**Status:** NOT IMPLEMENTED
**Issue:** No automatic detection of TrueColor support
**Impact:** May send RGB sequences to terminals that don't support them
**Action:**
- [ ] Check COLORTERM environment variable
- [ ] Query terminal capabilities (DA1/DA2)
- [ ] Provide Color.supports_truecolor? method
- [ ] Auto-downgrade RGB to ANSI-256 when needed

---

## Priority 5: Advanced Features (Backlog)

### P5.1 - Scroll Regions
- [ ] Set scrolling region (CSR capability)
- [ ] Scroll up/down within region
- [ ] Preserve content outside region

### P5.2 - ACS Box Drawing Characters
- [ ] Use terminfo `acsc` capability
- [ ] Map line-drawing characters to ACS
- [ ] Provide box-drawing helper methods

### P5.3 - OSC 8 Hyperlinks
- [ ] Add hyperlink support with OSC 8 sequences
- [ ] Hyperlink IDs for proper tracking
- [ ] Methods: start_hyperlink(url), end_hyperlink

### P5.4 - Extended Underline Styles (SGR 4:x)
- [ ] Single, double, curly, dotted, dashed underlines
- [ ] Underline color (SGR 58)
- [ ] Requires modern terminal support detection

### P5.5 - Image Protocol Support (Kitty/Sixel)
- [ ] Kitty graphics protocol
- [ ] Sixel support for legacy terminals
- [ ] Image placement and scaling

---

## Priority 6: Performance & Optimization

### P6.1 - Cell Structure Optimization 🟡 INVESTIGATE
**Status:** Needs profiling
**Issue:** Cell struct uses separate fields (char, fg, bg, attr)
**Potential:** Packed representation could improve cache locality
**Action:**
- [ ] Profile current Cell memory layout
- [ ] Benchmark packed vs unpacked representation
- [ ] Consider union for color (24-bit RGB in Int32)
- [ ] Measure cache miss rates for large buffers

### P6.2 - String Pooling for Escape Sequences
**Status:** Needs investigation
**Issue:** Escape sequences regenerated on each call
**Potential:** Intern common sequences for reduced allocation
**Action:**
- [ ] Profile escape sequence allocation rates
- [ ] Implement string interning for common sequences
- [ ] Benchmark memory vs performance tradeoff

### P6.3 - SIMD Color Conversion
**Status:** Future consideration
**Issue:** RGB to ANSI-256 conversion involves many comparisons
**Action:**
- [ ] Profile color conversion hot paths
- [ ] Investigate Crystal SIMD support
- [ ] Consider lookup table optimization

---

## Priority 8: Concurrency & Async Architecture ✅ COMPLETE

> **📄 Design Document:** See [`docs/design/async-event-system.md`](docs/design/async-event-system.md) for complete specification.
> **📄 Implementation Tracker:** See [`events-epic.md`](events-epic.md) for detailed task breakdown.

Crystal provides lightweight fibers (cooperative coroutines) and channels for safe inter-fiber communication. The async event system is now fully implemented.

### Current Async Usage

| Component | Status | Implementation |
|-----------|--------|----------------|
| Logging | ✅ Async dispatch | SafeFileIO with graceful shutdown |
| Input Reader | ✅ Async fiber | Event::Source::Input with named fiber |
| SIGWINCH | ✅ Implemented | Event::Source::Resize with signal + polling |
| Event Loop | ✅ Channel-based | Event::Loop multiplexer with select |
| Timer/Tick | ✅ Implemented | Event::Source::Timer (sleep-based) |
| SystemTimer | ✅ Implemented | Event::Source::SystemTimer (kernel timerfd/kqueue) |
| Custom Sources | ✅ Supported | `add_event_source` / `remove_event_source` API |

### P8.1 - SIGWINCH Resize Events with Channel ✅ COMPLETED
**Implementation:** `Event::Source::Resize` in `src/termisu/event/source/resize.cr`
- Hybrid SIGWINCH signal + polling (100ms fallback)
- Tracks old dimensions for `Event::Resize.changed?`
- Thread-safe with `Atomic(Bool)` and `compare_and_set`

### P8.2 - Unified Event Channel Architecture ✅ COMPLETED
**Implementation:** `Event::Loop` in `src/termisu/event/loop.cr`
- `Event::Any` union type: `Key | Mouse | Resize | Tick`
- `poll_event`, `poll_event(timeout)`, `wait_event` APIs
- `try_poll_event` for non-blocking (select/else pattern)
- `each_event(&)` iterator for event loops

### P8.3 - Async Input Reader Fiber ✅ COMPLETED
**Implementation:** `Event::Source::Input` in `src/termisu/event/source/input.cr`
- Named fiber "termisu-input" for debugging
- Thread-safe lifecycle with `Atomic(Bool)`
- Handles `Channel::ClosedError` gracefully

### P8.4 - Timer/Tick Channel for Animations ✅ COMPLETED
**Implementation:** `Event::Source::Timer` in `src/termisu/event/source/timer.cr`
- Sleep-based timer with configurable interval (default 16ms for ~60 FPS)
- `Event::Tick` with `frame`, `elapsed`, `delta`, `missed_ticks`
- Runtime interval changes via `timer_interval=`
- API: `enable_timer`, `disable_timer`, `timer_enabled?`

### P8.5 - Fan-In Event Multiplexer ✅ COMPLETED
**Implementation:** `Event::Loop` + custom source API
- `add_event_source(source)` - add custom Event::Source
- `remove_event_source(source)` - remove source
- Sources auto-start when loop is running
- Example in README shows custom source pattern

### P8.6 - Kernel-Level SystemTimer ✅ COMPLETED
**Implementation:** `Event::Source::SystemTimer` in `src/termisu/event/source/system_timer.cr`
- Kernel-level timing via timerfd/epoll (Linux) or kqueue (macOS/BSD)
- Sub-millisecond precision, reliable up to ~90 FPS
- `missed_ticks` field for detecting slow frame processing
- Poll fallback for unsupported platforms
- API: `enable_system_timer`, shared `disable_timer`, `timer_interval=`
- Poller abstraction: `Event::Poller::Epoll`, `Event::Poller::Kqueue`, `Event::Poller::Poll`

### P8.7 - Async Logging Batching 🟢 LOW PRIORITY (Deferred)
**Status:** Partial (async dispatch exists)
**Rationale:** Current SafeFileIO is sufficient for most use cases

---

## Async Architecture Summary

### Current Event Loop Pattern (v0.1.0+)

```crystal
termisu = Termisu.new
termisu.enable_timer(16.milliseconds)  # Optional: ~60 FPS for animations

termisu.each_event do |event|
  case event
  when Termisu::Event::Key
    break if event.key.escape?
    handle_key(event)
  when Termisu::Event::Mouse
    handle_mouse(event)
  when Termisu::Event::Resize
    termisu.resize(event.width, event.height)
    termisu.sync
  when Termisu::Event::Tick
    animate(event.delta)
    termisu.render
  end
end

termisu.close
```

### Non-Blocking Pattern (Game Loops)

```crystal
# Process all pending events without blocking
while event = termisu.try_poll_event
  handle_event(event)
end

# Then do frame update
update_game_state
render_frame
```

### Event API Summary

| Method | Behavior |
|--------|----------|
| `poll_event` | Blocking, returns `Event::Any` |
| `poll_event(timeout)` | With timeout, returns `Event::Any?` |
| `try_poll_event` | Non-blocking (select/else), returns `Event::Any?` |
| `wait_event` | Alias for blocking `poll_event` |
| `each_event(&)` | Iterator yielding events |

---

## Priority 7: Infrastructure & Quality

### P7.1 - Fix Benchmark Suite ✅ COMPLETED
**File:** `bench/suites/buffer_suite.cr`
**Issue:** NullRenderer was missing abstract methods added in P3.4
**Solution:** Added `enable_dim`, `enable_cursive`, `enable_hidden` to NullRenderer
**Benchmark Results (2024-12, after hot path log removal):**
- Cell operations: ~28M ops/sec (35ns per cell)
- Buffer clear: 280K/s (small) to 44K/s (large)
- Render diff: 80K/s (no changes) to 72K/s (10% changed)
- Resize: 12-16K ops/sec
- Cursor ops: 28-32M ops/sec

### P7.2 - Add Integration Tests
**Status:** Partial
**Action:**
- [ ] End-to-end rendering tests with PTY
- [ ] Color conversion round-trip tests
- [ ] Full event parsing integration tests
- [ ] Resize handling tests

### P7.3 - Improve Error Types
**Status:** Partial (ParseError, IOError done)
**Action:**
- [ ] Create ValidationError for input validation
- [ ] Create CapabilityError for missing terminfo capabilities
- [ ] Standardize error hierarchy

### P7.4 - CI/CD Improvements
**Status:** Partial
**Action:**
- [ ] Add release automation
- [ ] Add changelog generation
- [ ] Add benchmark CI job

### P7.5 - Documentation
**Status:** Partial progress
**Completed:**
- [x] `CLAUDE.md` - AI agent guidance with architecture overview
- [x] `AGENTS.md` - AI coding agent instructions
- [x] `CONTRIBUTING.md` - Updated with hace commands
- [x] `docs/ARCHITECTURE.md` - Architecture documentation
- [x] `docs/API.md` - API reference
- [x] `docs/DEVELOPMENT.md` - Development guide
- [x] `docs/design/async-event-system.md` - Async system design spec
**Remaining:**
- [ ] Add getting started guide (quick tutorial)
- [ ] Add more usage examples to README
- [ ] Add docstrings to all public methods

---

## Recently Completed

### 2025-12 Session 4 (Kernel-Level SystemTimer)
- [x] **P8.6** SystemTimer implementation with kernel-level timing
  - Added `Event::Source::SystemTimer` using timerfd/epoll (Linux) and kqueue (macOS/BSD)
  - Added `Event::Poller` abstraction with Epoll, Kqueue, and Poll backends
  - Added `missed_ticks` field to `Event::Tick` for frame drop detection
  - Sub-millisecond precision, reliable up to ~90 FPS (limited by terminal I/O)
  - API: `enable_system_timer`, unified `disable_timer`, `timer_interval=`
  - Comprehensive specs (25 tests for SystemTimer)
  - Updated animation.cr example with runtime timer switching
  - Benchmarking shows ~91 FPS ceiling due to terminal I/O overhead

### 2025-12 Session 3 (Synchronized Updates - DEC Mode 2026)
- [x] **P4.3** Synchronized Updates implementation
  - Added BSU/ESU constants (`\e[?2026h` / `\e[?2026l`) to Terminal
  - Added `@sync_updates` flag (enabled by default)
  - Wrapped `render()` and `sync()` methods with BSU/ESU sequences
  - Added `sync_updates?` getter and `sync_updates=` setter
  - Added `sync_updates` constructor parameter to Terminal and Termisu
  - Created `dec-plan.md` design document
  - Added 7 new tests (904 total, +51 from 853)

### 2025-12 Session 2 (Strikethrough Attribute)
- [x] **P4.4** Strikethrough attribute implementation
  - Added `Strikethrough = 128` to Attribute flags
  - Added `smxx` to REQUIRED_FUNCS and builtin fallbacks
  - Added `strikethrough_seq` to Terminfo
  - Added `enable_strikethrough` to Renderer/Terminal
  - Updated RenderState for attribute application
  - Added 9 new tests (853 total, +9 from 844)
  - Updated examples: showcase.cr, simple.cr
  - Updated README.md documentation

### 2025-12 Session (hace Migration & Documentation)
- [x] Migrated from task-go (Taskfile.yml) to hace (Hacefile.yml)
- [x] Created `CLAUDE.md` for AI agent guidance
- [x] Created `AGENTS.md` for AI coding agents
- [x] Updated `CONTRIBUTING.md` with hace commands
- [x] Fixed binary content in `docs/DEVELOPMENT.md` project structure
- [x] Added profiling tasks to Hacefile (perf, callgrind, memcheck)
- [x] Added parallel task execution support

**Current Stats (2025-12):**
- **Test Coverage:** 979 tests passing, 0 failures
- **Code Quality:** ameba clean (111 files, 0 issues)
- **Source Lines:** ~6,200 (47 files)
- **Test Lines:** ~7,800 (38 spec files)
- **Test-to-Code Ratio:** 1.26x

### 2024-12 Session 2 (Async Event System)
- [x] **P8.1-P8.5** Complete async event system implementation
  - Event::Source abstract class with Input, Resize, Timer implementations
  - Event::Loop multiplexer with channel-based event routing
  - Event::Any union type (Key | Mouse | Resize | Tick)
  - SIGWINCH resize handling with hybrid signal + polling
  - Timer source for animations (~60 FPS default)
  - Custom event source API
- [x] `try_poll_event` non-blocking method (select/else pattern)
- [x] Case-insensitive letter matching (`key.q?` matches 'q' or 'Q')
- [x] Comprehensive README API documentation
- [x] `examples/animation.cr` bouncing ball demo
- [x] `AGENTS.md` for AI agent instructions
- [x] Ameba lint cleanup (26 violations fixed)
  - Whitespace around macro expressions
  - Redundant nil in control expressions
  - Redundant self references
  - Short block notation

### 2024-12 Session 1 (Analysis & Cleanup)
- [x] P7.1 Benchmark suite fixed (NullRenderer missing enable_dim, enable_cursive, enable_hidden)
- [x] Hot path logging removed - 17 trace/debug logs removed
- [x] Code quality audit completed

---

## Previously Completed

- [x] Structured logging system (async/sync dispatch, SafeFileIO)
- [x] P3.3 Terminfo cursor movement with full tparm processor
- [x] P3.4 Extended attribute support (dim, italic, hidden)
- [x] P3.2 Complete input parsing (CSI, SS3, Kitty, modifyOtherKeys)
- [x] P3.1 Mouse input (SGR, normal mode)
- [x] P2.2 Terminal state caching
- [x] P2.1 Attribute rendering optimization with RenderState
- [x] P1.3 EINTR handling in Reader
- [x] P1.2 Cursor bounds clamping
- [x] P1.1 Parser error handling with ParseError
- [x] Concurrent benchmark suite (needs NullRenderer fix)
- [x] Full color support (ANSI-8, ANSI-256, RGB)
- [x] Color modular architecture
- [x] GitHub Pages documentation workflow
- [x] Lefthook pre-commit hooks

---

## Version Roadmap

### v0.0.2 (Current - Alpha) ✅ COMPLETE
- ✅ Core terminal control
- ✅ Double-buffered rendering
- ✅ Full terminfo support
- ✅ Complete input handling (keyboard, mouse)
- ✅ Color support (8, 256, RGB)
- ✅ Text attributes (8 attributes including strikethrough)
- ✅ **Async event system** (P8.1-P8.5)
  - ✅ Event::Loop multiplexer
  - ✅ Event::Source abstraction (Input, Resize, Timer)
  - ✅ SIGWINCH resize handling
  - ✅ Timer/tick for animations
  - ✅ Custom event source API
- ✅ hace task runner with parallel execution
- ✅ AI agent documentation (CLAUDE.md, AGENTS.md)

### v0.1.0 (Next - Beta) - Polish & Features
- [ ] P4.2 Unicode/wide character support
- [x] P4.3 Synchronized updates (DEC 2026) ✅
- [x] P4.4 Strikethrough attribute ✅
- [ ] P7.5 Documentation improvements (getting started guide)

### v0.2.0 (Future) - Extended Input
- [ ] P4.5 Bracket paste mode
- [ ] P4.6 Focus tracking
- [ ] P4.7 Extended color detection

### v0.3.0 (Future) - Advanced Features
- [ ] P5.1 Scroll regions
- [ ] P5.2 ACS box drawing
- [ ] P5.3 OSC 8 hyperlinks
- [ ] P5.4 Extended underline styles
- [ ] P5.5 Image protocol support (Kitty/Sixel)

### v1.0.0 (Stable)
- [ ] All P4 + P5 features complete
- [ ] Comprehensive documentation
- [ ] Widget system (optional)
- [ ] Platform compatibility (Windows ConPTY)

---

## Priority 9: Code Quality & Technical Debt

### Code Quality Analysis (2024-12 Audit)

**Overall Assessment: GOOD** - Codebase is well-structured with excellent patterns. Minor improvements identified.

#### 9.1 Minor Code Smells

##### 9.1.1 - Cursor `show` Method Conditional Check 🟢 ACCEPTABLE
**File:** `src/termisu/cursor.cr:55-63`
**Pattern:** `.as(Int32)` after nil check
```crystal
if @last_x && @last_y
  @x = @last_x.as(Int32)
  @y = @last_y.as(Int32)
```
**Analysis:** This is correct - the `.as(Int32)` is explicit and readable. Crystal's flow analysis doesn't narrow instance variables in conditionals, so the cast is required.
**Status:** Acceptable as-is

##### 9.1.2 - Parser `parse_sgr_mouse` Complexity ✅ FIXED
**File:** `src/termisu/input/parser.cr:364-417`
**Issue:** Method flagged by ameba `Metrics/CyclomaticComplexity`
**Solution:** Refactored using SRP into three focused methods:
```crystal
# Main entry point - now ~2 lines, minimal complexity
private def parse_sgr_mouse : Event
  result = read_sgr_sequence
  return Events::Key.new(Key::Unknown) unless result
  raw_params, is_release = result
  parse_sgr_params_to_event(raw_params, is_release) || Events::Key.new(Key::Unknown)
end

# Single responsibility: read bytes until terminator
private def read_sgr_sequence : {String, Bool}?

# Single responsibility: parse params and create event
private def parse_sgr_params_to_event(raw_params : String, is_release : Bool) : Events::Mouse?
```
**Benefits:**
- Removed `ameba:disable` comment - passes lint naturally
- Each method has single responsibility (SOLID: SRP)
- Testable units: reading vs parsing are now separate
- Also fixed: wheel check now includes WheelLeft/WheelRight (was missing)

##### 9.1.3 - Termios Pointer Pattern 🟢 TRIVIAL
**File:** `src/termisu/termios.cr:89-95`
```crystal
private def set_attrs(tios : LibC::Termios)
  tios_copy = tios  # Creates copy just to get a pointer
  if LibC.tcsetattr(@fd, LibC::TCSAFLUSH, pointerof(tios_copy)) != 0
```
**Analysis:** This is actually correct Crystal pattern for FFI, not a smell

##### 9.1.4 - Terminfo Parser String Allocation ✅ FIXED
**File:** `src/termisu/terminfo/parser.cr:266-271`
**Issue:** Dynamic array growth during parsing
**Solution:** Used `String.build` with variable binding pattern:
```crystal
String.build do |builder|
  while (byte = io.read_byte) && byte != 0
    builder.write_byte(byte)
  end
end
```
**Status:** Fixed - cleaner, better memory allocation, idiomatic Crystal

##### 9.1.5 - Color Conversion Threshold Magic Numbers ✅ FIXED
**File:** `src/termisu/color/conversions.cr:12-14`
**Issue:** Magic number without named constant
**Solution:** Added documented constant:
```crystal
# Threshold for RGB to ANSI-8 color mapping.
# Values >= 128 are considered "on" for that color channel.
ANSI8_THRESHOLD = 128_u8
```
**Status:** Fixed - self-documenting constant with clear explanation

#### 9.2 Performance Opportunities (All Low Priority)

##### 9.2.1 - Buffer Clear Loop 🟢 LOW PRIORITY
**File:** `src/termisu/buffer.cr:85-89`
```crystal
def clear
  @back.size.times do |index|
    @back[index] = Cell.default
  end
end
```
**Potential:** Could use `Array#fill` but Crystal optimizes the loop well
**Benchmark:** 280K ops/sec (small) - already performant
**Action:** Keep as-is; readability > micro-optimization

##### 9.2.2 - Color Struct Allocation 🟢 LOW PRIORITY
**File:** `src/termisu/color.cr`
**Analysis:** Color is a struct (value type), not heap allocated
**No Issue:** Already optimal - uses value semantics throughout

##### 9.2.3 - String::Builder in Parser 🟢 ACCEPTABLE
**File:** `src/termisu/input/parser.cr:187, 376`
```crystal
def parse_csi_sequence : Event
  buffer = String::Builder.new  # Allocates new builder each call
```
**Analysis:** Investigated optimization - not worth implementing because:
1. **No clear() method** - String::Builder lacks reset capability (verified in Crystal 1.14 API)
2. **Tiny allocations** - MAX_SEQUENCE_LENGTH is 32 bytes, typical sequences are 3-10 bytes
3. **Short-lived objects** - GC generation 0 handles these efficiently
4. **Alternatives add complexity**:
   - IO::Memory has `clear` but isn't optimized for string building
   - Manual Bytes buffer with position tracking adds bug surface
   - Buffer pooling overkill for 32-byte objects
5. **Current pattern is idiomatic** - matches `String.build` usage elsewhere in Crystal
**Status:** Acceptable - premature optimization would violate KISS/YAGNI

##### 9.2.4 - Tparm Static Variable Storage 🟢 LOW PRIORITY
**File:** `src/termisu/terminfo/tparm/processor.cr:45`
```crystal
@@static_storage : Hash(Char, Int64) = {} of Char => Int64
```
**Issue:** Class variable for static vars shared across all calls
**Impact:** Minimal - rarely used feature (static vars in terminfo are uncommon)
**Note:** Proper design for terminfo spec compliance

#### 9.3 Missing Defensive Patterns 🟡 MINOR

##### 9.3.1 - Reader Buffer Size Validation
**File:** `src/termisu/reader.cr:37`
```crystal
def initialize(@fd : Int32, buffer_size : Int32 = 128)
  @buffer = Bytes.new(buffer_size)
```
**Issue:** No validation that `buffer_size > 0`
**Impact:** Very low (internal constructor)
**Action:** Consider adding `raise ArgumentError.new("buffer_size must be positive")` for robustness

##### 9.3.2 - Terminal Cleanup Guarantee
**File:** `src/termisu/terminal.cr`
**Issue:** No finalize/at_exit to guarantee raw mode restoration
**Impact:** If user forgets to call `close`, terminal may be left in raw mode
**Action:** Consider adding `at_exit { disable_raw_mode }` pattern or document requirement

##### 9.3.3 - Buffer Dimension Validation
**File:** `src/termisu/buffer.cr:38-46`
```crystal
def initialize(@width : Int32, @height : Int32)
  size = @width * @height
  @front = Array(Cell).new(size) { Cell.default }
```
**Issue:** No validation that width/height > 0
**Impact:** Minimal - terminal always provides valid dimensions
**Action:** Consider adding defensive check for robustness

##### 9.3.4 - Terminfo TERM Environment Validation
**File:** `src/termisu/terminfo.cr:43`
```crystal
term_name = ENV["TERM"]? || raise Termisu::Error.new("TERM environment variable not set")
```
**Issue:** Good error message but could validate TERM content
**Impact:** Minimal - Database.new handles invalid TERM gracefully
**Status:** ✅ Already acceptable

#### 9.4 Good Patterns Already Present ✅

| Pattern | Location | Implementation |
|---------|----------|----------------|
| **Idempotent operations** | Backend#enable_raw_mode | Guards against double-enable |
| **Defensive EINTR handling** | Reader#fill_buffer | Retry loop with max limit |
| **Clear error types** | error.cr | ParseError, IOError with context |
| **State caching** | Terminal, RenderState | Prevents redundant escape sequences |
| **Bounds clamping** | Buffer#set_cursor, Cursor#clamp | Safe coordinate handling |
| **Platform abstraction** | TTY#USE_RDWR | BSD vs Linux handling |
| **Async logging** | log.cr | SafeFileIO wrapper prevents crashes |
| **Hash-based dispatch** | Input::Parser | O(1) key lookups |
| **Double buffering** | Buffer | Front/back with diff rendering |
| **Capability caching** | Terminfo | 12 cached parametrized caps |
| **Value types** | Color, Cell, RenderState | Struct for stack allocation |
| **Macro-based constants** | TTY, LibC | Compile-time platform detection |
| **@[AlwaysInline]** | Tparm::Processor | Hot path optimization |
| **Event union type** | events.cr | Type-safe event handling |
| **Modifier flags enum** | Modifier | Bitwise operations with type safety |

### Summary

**No Critical Issues Found.** The codebase demonstrates solid engineering:
- Well-structured modules with clear responsibilities
- Good error handling patterns
- Performance optimizations where they matter
- Clean abstractions (Renderer interface, Event union type)
- Proper platform handling
- Value types used appropriately for stack allocation

**Code Smells Fixed (2024-12):**
- ✅ 9.1.2 - Parser complexity (refactored into 3 SRP methods, removed ameba:disable)
- ✅ 9.1.4 - Terminfo parser string (String.build)
- ✅ 9.1.5 - Color conversion constant (ANSI8_THRESHOLD)

**Acceptable Patterns (no change needed):**
- 🟢 9.1.1 - Cursor `.as(Int32)` cast (explicit, required by Crystal)
- 🟢 9.1.3 - Termios pointer (correct FFI pattern)

**Remaining Minor Technical Debt:** ~2-3 hours for 9.3 defensive patterns

---

## Contributing

Pick any item marked with `[ ]`. Priority order for contributions:
1. **P4.2** - Unicode/wide character support (high impact)
2. **P5.5** - Image protocols (Kitty/Sixel) (high impact for rich UIs)
3. **P7.5** - Documentation improvements
4. **P4.5** - Bracket paste mode

Create a PR with tests for any changes.
