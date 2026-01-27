# PITFALLS.md - Common TUI Library Mistakes to Avoid

## The Termbox Author's Acknowledged Flaws

> "The abstraction itself is not perfect and it may create problems in certain areas. The most sensitive ones are copy & pasting and wide characters (mostly Chinese, Japanese, Korean (CJK) characters)."
> — nsf, termbox README

### 1. Cell Model vs Text Selection

**Problem:** The cell-based model doesn't align with text semantics.

When you render:
```
┌─────────────┐
│ Hello World │
└─────────────┘
```

User selects "Hello World" → but terminal sees cells, not words. Copy-paste can produce garbage.

**Termisu Approach:**
- Accept limitation for pseudo-GUI focus
- Provide bracket paste mode (P4.5) to at least detect paste events
- Document that TUI ≠ CLI

### 2. Wide Character Support (CJK)

**Problem:** CJK characters require 2 cells, emoji can require 2+.

```
A B C 你好! 🎉
█ █ █ █ █ █ █
1 2 3 4 5 6 7  ← cell count wrong!
```

**Termisu Status:** 🟡 Priority 4.2 (Unicode/wide characters)

**Solution Plan:**
```crystal
# Add wcwidth handling
width = Unicode.wcwidth(char)  # returns 0, 1, or 2
case width
when 0 then # combining char, skip
when 1 then # normal
when 2 then # wide,占用2 cells
end

# Track cell adjacency
buffer.set_cell(x, y, char, width: 2)
buffer.set_cell(x+1, y, Cell::Continuation)
```

---

## Common TUI Library Pitfalls

### 1. Flicker Rendering

**Mistake:** Emitting escape sequences for every cell every frame.

```crystal
# BAD - flicker city
termisu.clear
height.times do |y|
  width.times do |x|
    emit_escape(cell)
  end
end
```

**Termisu Solution:** Double buffering with diff-based rendering.

```crystal
# GOOD - only changed cells
front_buffer.diff(back_buffer).each do |change|
  emit_escape(change)
end
front_buffer = back_buffer
```

**Status:** ✅ Implemented

### 2. Blocking the UI

**Mistake:** Synchronous I/O in event loop freezes everything.

```go
// BAD - blocks entire UI
if event := termbox.PollEvent(); event.Type == termbox.EventKey {
    result := http.Get("http://api.example.com")  // BLOCKS!
}
```

**Termisu Solution:** Fiber-based async.

```crystal
# GOOD - non-blocking
spawn do
  result = HTTP::Client.get("http://api.example.com")
  response_channel.send(result)
end

# Event loop continues, multiplexing input and async response
select
when event = Termisu.next_event
  case event
  when Termisu::Event::Key
    # handle input
  end
when result = response_channel.receive
  # handle async result
end
```

**Status:** ✅ Implemented

### 3. Terminal State Corruption

**Mistake:** Forgetting to restore terminal on crash/exception.

```crystal
# BAD - terminal left broken if exception raised
termisu = Termisu.new
do_something_that_might_raise
termisu.close
```

**Termisu Solution:** Documented RAII pattern + state caching.

```crystal
# GOOD - always restore
termisu = Termisu.new
begin
  do_work
ensure
  termisu.close  # runs even if exception raised
end
```

**Improvement Opportunity:** Add `at_exit` hook (M1 in CONCERNS.md)

**Status:** 🟡 Partial (user must use ensure)

### 4. EINTR = Lost Data

**Mistake:** Not retrying on interrupted system calls.

```c
// BAD - EINTR treated as EOF
n = read(fd, buf, size);
if (n <= 0) return EOF;  // WRONG!
```

**Termisu Solution:** Retry loop in Reader.

```crystal
# GOOD - EINTR retry
loop do
  n = LibC.read(@fd, buffer, size)

  case n
  when 0 then return EOF
  when -1
    if Errno.value == Errno::EINTR
      next  # RETRY
    else
      raise Error.new("read failed")
    end
  else
    return n
  end
end
```

**Status:** ✅ Implemented

### 5. Escape Sequence Bloat

**Mistake:** Emitting redundant escape sequences.

```crystal
# BAD - redundant resets
emit("\e[31m")  # red
emit("A")
emit("\e[0m")   # reset
emit("\e[31m")  # red again!
emit("B")
emit("\e[0m")   # reset
```

**Termisu Solution:** RenderState caching.

```crystal
# GOOD - state-aware
@state.fg = nil

def set_cell(char, fg, bg, attr)
  return if fg == @state.fg && bg == @state.bg && attr == @state.attr

  emit("\e[31m")  # only if actually changing
  @state.fg = fg
end
```

**Status:** ✅ Implemented

### 6. Platform Fragmentation

**Mistake:** Hardcoding Linux-only syscalls.

```crystal
# BAD - crashes on macOS
LibC.epoll_create1(0)  # Linux only!
```

**Termisu Solution:** Conditional compilation + fallbacks.

```crystal
# GOOD - platform-aware
{% if flag?(:linux) %}
  require "./poller/linux"
{% elsif flag?(:darwin) %}
  require "./poller/kqueue"
{% else %}
  require "./poller/poll"  # portable fallback
{% end %}
```

**Status:** ✅ Implemented

### 7. Magic Numbers

**Mistake:** Unexplained constants.

```crystal
# BAD - what is 48?
if color < 48
  ansi8_mode
else
  ansi256_mode
end
```

**Termisu Solution:** Named constants.

```crystal
# GOOD - self-documenting
ANSI8_THRESHOLD = 48

if color < ANSI8_THRESHOLD
  ansi8_mode
else
  ansi256_mode
end
```

**Status:** ✅ Fixed (was previously identified issue)

### 8. Memory Leaks in Async Code

**Mistake:** Fibers that never terminate.

```crystal
# BAD - fiber orphaned on close
spawn do
  loop do
    output.send(TickEvent.new)
    sleep 16.milliseconds
  end
end
# If Termisu closed, fiber keeps running!
```

**Termisu Solution:** Atomic stop flag + ensure cleanup.

```crystal
# GOOD - graceful shutdown
class TimerSource < Event::Source
  @running = Atomic(Bool).new(false)

  def start(output)
    @running.set_true
    @fiber = spawn do
      while @running.true?
        output.send(TickEvent.new)
        sleep 16.milliseconds
      end
    end
  end

  def stop
    @running.set_false
    @fiber.try(&.join)  # wait for cleanup
  end
end
```

**Status:** ✅ Implemented

### 9. Diff Algorithm O(n²) Complexity

**Mistake:** Naive cell-by-cell comparison.

```crystal
# BAD - checks every cell
height.times do |y|
  width.times do |x|
    if front[y][x] != back[y][x]
      emit_change(x, y, back[y][x])
    end
  end
end
# For 80x24 terminal: 1920 comparisons every frame!
```

**Termisu Solution:** Row-based diffing + batch runs.

```crystal
# GOOD - skip unchanged rows
height.times do |y|
  next if front[y] == back[y]  # ROW-LEVEL SKIP
  # then process changed cells in row
end
```

**Status:** ✅ Implemented

### 10. Input Parser Complexity

**Mistake:** Monolithic parser handling all escape sequences.

```crystal
# BAD - 500-line method
def parse_input(bytes)
  case bytes[0]
  when '\e' then
    if bytes[1] == '[' then
      if bytes[2] == '1' then
        if bytes[3] == ';' then
          # 50 levels of nesting!
```

**Termisu Solution:** Split into SRP methods.

```crystal
# GOOD - single responsibility
def parse_input(bytes)
  case bytes[0]
  when '\e' then parse_escape(bytes)
  else           parse_char(bytes[0])
  end
end

private def parse_escape(bytes)
  case bytes[1]
  when '[' then parse_csi(bytes)
  when 'O'  then parse_ss3(bytes)
  else           parse_plain_escape
  end
end
```

**Status:** ✅ Refactored (was previously identified issue)

---

## Termisu-Specific Pitfalls Avoided

### Design Decisions That Paid Off

| Decision | Why It Worked |
|----------|---------------|
| **Event::Any union type** | Type-safe pattern matching, compiler verification |
| **Structs for value types** | Stack allocation, no GC pressure on hot path |
| **Zero runtime deps** | Easy sharding, no version conflicts |
| **Separate Reader/Parser** | Testable input parsing in isolation |
| **Renderer abstraction** | Mock renderers for unit testing |
| **Terminfo with fallback** | Works everywhere, not just well-known terminals |
| **Fiber-based async** | Crystal's strength, no callback hell |
| **Source file per component** | Easy to navigate, clear responsibility |

---

## Pitfalls Still to Watch

### Unicode Implementation (P4.2)

**Risk:** Getting wcwidth wrong for complex emoji.

```crystal
# Tricky cases
"👨‍👩‍👧‍👦"  # family emoji (multi-codepoint, but 2 cells?)
"🇺🇸"     # flag emoji (2 regional indicators = 4 cells? or 1?)
"नमस्ते"   # Devanagari with combining marks
```

**Mitigation:** Use established `wcwidth` implementation, don't DIY.

### Kernel Timer Portability

**Risk:** timerfd/kqueue not available on all platforms.

**Current Status:** Falls back to sleep-based timer automatically.

**Future Watch:** OpenBSD support, new platforms.

### Memory Pressure

**Risk:** Large buffers + many fibers = GC pressure.

**Current Mitigation:**
- Structs for Cell/Color (stack allocation)
- Channel buffers bounded
- Fiber lifecycle managed

**Future Consideration:** Object pooling for very large terminals.

---

## Anti-Patterns to Avoid in Future Development

### 1. "Just Add a Flag"

Don't:
```crystal
attr |= BOLD
attr |= ITALIC
attr |= BLINK
# 8 separate bit operations
```

Do:
```crystal
attr = Bold | Italic | Blink  # single assignment
```

### 2. "Silent Failures"

Don't:
```crystal
def enable_mouse
  # returns nothing, no indication if failed
end
```

Do:
```crystal
def enable_mouse : Bool
  # return true on success, raise on failure
end
```

### 3. "Global State"

Don't:
```crystal
@@current_terminal = nil  # shared across all instances
```

Do:
```crystal
@terminal  # per-instance state
```

Termisu already avoids this!

### 4. "Premature Optimization"

Don't optimize before profiling. Termisu's benchmarks (bench/buffer_bench.cr) prove current rendering is fast enough.

### 5. "Testing via Manual Inspection"

Don't rely on running examples to verify behavior. Termisu's mock renderers enable unit testing without terminal.

---

## Sources

- [nsf/termbox README](https://github.com/nsf/termbox) - Author's acknowledged limitations
- [Termbox-go README](https://github.com/nsf/termbox-go) - Maintenance lessons
- Termisu codebase analysis - What worked, what didn't
- TODO.md - Open issues and priorities

---

*Last updated: 2025-01-26 - Pitfall analysis for Termisu development*
