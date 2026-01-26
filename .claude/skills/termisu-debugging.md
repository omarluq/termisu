# Termisu Debugging

Debugging techniques for Termisu TUI applications and library internals.

## When to Use

- "Debug rendering"
- "Debug events"
- "Terminal not restoring"
- "Garbage on screen"
- "Event not firing"
- "Memory leak"

## Logging

### Enable Debug Logging

```bash
# Enable logging
TERMISU_LOG_LEVEL=debug TERMISU_LOG_FILE=/tmp/termisu.log crystal run examples/demo.cr

# Watch logs in real-time
tail -f /tmp/termisu.log

# Sync mode for real-time debugging
TERMISU_LOG_SYNC=true TERMISU_LOG_FILE=/tmp/termisu.log crystal run examples/demo.cr
```

### Log Levels

| Level | Purpose |
|-------|---------|
| `trace` | Very verbose, function entry/exit |
| `debug` | Detailed diagnostic info |
| `info` | General informational messages |
| `warn` | Warning messages |
| `error` | Error conditions |
| `fatal` | Critical errors |
| `none` | Disable logging |

### Component-Specific Logging

```crystal
# Fine-grained logging by component
log = Log.for("termisu.buffer")
log.debug { "Cell changed at #{x}, #{y}" }

log = Log.for("termisu.event.input")
log.debug { "Parsed key: #{key}" }
```

## Debugging Rendering

### Visualize Cell Buffer

```crystal
# Dump buffer contents for debugging
def dump_buffer(termisu)
  width, height = termisu.size

  height.times do |y|
    row = (0...width).map do |x|
      cell = termisu.get_cell(x, y)
      cell ? cell.char : '?'
    end.join
    puts row
  end
end
```

### Track Changed Cells

```crystal
# See what cells are being rendered
class DebugRenderer
  include Renderer

  def initialize(@io : IO = STDOUT)
    @cell_count = 0
    @move_count = 0
    @fg_count = 0
    @bg_count = 0
  end

  def write(char : Char)
    @io << char
    @cell_count += 1
  end

  def move(x : Int32, y : Int32)
    @io << "\e[#{y + 1};#{x + 1}H"
    @move_count += 1
  end

  def foreground=(color : Color?)
    @io << color.to_s
    @fg_count += 1
  end

  def flush
    @io.flush
    puts "\n[Debug: #{@cell_count} cells, #{@move_count} moves, #{@fg_count} fg changes]"
  end

  def reset
    @cell_count = 0
    @move_count = 0
    @fg_count = 0
  end
end

# Usage
renderer = DebugRenderer.new
buffer.render_to(renderer)
# Output: [Debug: 150 cells, 5 moves, 3 fg changes]
```

### Capture Render Output

```crystal
# Capture all escape sequences
output = IO::Memory.new
renderer = RenderState.new(output)
buffer.render_to(renderer)

puts output.to_s
# Shows: \e[10;5H\e[31mX\e[39m ...
```

## Debugging Events

### Log All Events

```crystal
loop do
  if event = termisu.poll_event(50)
    puts "Event: #{event.class}"

    case event
    when Termisu::Event::Key
      puts "  Key: #{event.key}"
      puts "  Ctrl: #{event.ctrl?}, Alt: #{event.alt?}, Shift: #{event.shift?}"

    when Termisu::Event::Mouse
      puts "  Mouse: x=#{event.x}, y=#{event.y}"
      puts "  Button: #{event.button}, Press: #{event.press?}"

    when Termisu::Event::Tick
      puts "  Tick: delta=#{event.delta.total_milliseconds}ms"
    end
  end
end
```

### Show Raw Input Bytes

```crystal
# See what bytes the terminal is sending
class DebugReader < Reader
  def read_byte(timeout : Time::Span? = nil) : UInt8?
    byte = super
    if byte
      printf "Read: 0x%02X (%c)\n", byte, byte >= 32 && byte < 127 ? byte.chr : '.'
    end
    byte
  end
end

# Usage
reader = DebugReader.new(tty)
parser = Parser.new(reader)
```

### Trace Event Flow

```crystal
# Add logging to event sources
class TracingInputSource < Event::Source::Input
  def start(output)
    Log.info { "Starting input source" }
    super
  end

  def stop
    Log.info { "Stopping input source" }
    super
  end
end
```

## Debugging Terminal State

### Check Terminal Mode

```crystal
puts "Alternate screen: #{termisu.alternate_screen?}"
puts "Raw mode: #{termisu.raw_mode?}"
puts "Mouse enabled: #{termisu.mouse_enabled?}"
puts "Enhanced keyboard: #{termisu.enhanced_keyboard?}"
puts "Timer enabled: #{termisu.timer_enabled?}"
puts "Timer interval: #{termisu.timer_interval}"
```

### Check Terminal Capabilities

```bash
# Query terminfo capabilities
infocmp -1 xterm-256color | grep -E "(colors|pairs)"

# Test color support
echo -e "\e[31mRed\e[0m"
echo -e "\e[38;2;255;0;128mTruecolor\e[0m"

# Test mouse
echo -e "\e[?1000h"  # Enable mouse
# Click and watch output
echo -e "\e[?1000l"  # Disable
```

### Restore Broken Terminal

```bash
# If terminal is messed up
reset

# Or
stty sane

# Or (most reliable)
tput reset
```

## Debugging Async Issues

### Fiber Deadlock

```crystal
# Check if fiber is stuck
spawn do
  loop do
    puts "Fiber alive: #{Time.monotonic}"
    sleep 1.second
  end
end

# If you don't see "Fiber alive" every second, fiber is blocked
```

### Channel Blocking

```crystal
# Non-blocking receive with timeout
select
  when value = channel.receive
    puts "Got: #{value}"
  when timeout(1.second)
    puts "Channel timeout - possible deadlock"
  end
```

### Event Source Not Producing

```crystal
# Check if source is running
source = Event::Source::Input.new(reader, parser)
source.start(channel)

puts "Running: #{source.running?}"  # Should be true

# Check fiber status
Fiber.list.each do |f|
  puts "Fiber: #{f.inspect}, state: #{f.state}"
end
```

## Debugging Memory

### Valgrind Memcheck

```bash
# Build with debug symbols
crystal build --debug examples/demo.cr -o demo

# Run with valgrind
valgrind --leak-check=full --show-leak-kinds=all ./demo

# Look for:
# - "definitely lost": memory leaks
# - "invalid read/write": use-after-free
# - "still reachable": might be OK (globals)
```

### Memory Profiling

```bash
# Massif (heap profiler)
valgrind --tool=massif ./demo

# Analyze
ms_print massif.out.xxxxx
```

## Common Issues and Solutions

### Screen Not Clearing

**Symptom:** Old text remains visible

**Diagnosis:**
```crystal
# Check if clear was called
termisu.clear
termisu.render  # Did you call render?
```

**Solution:** Always call `render` after `clear`.

### Garbage Characters on Screen

**Symptom:** Random characters appear

**Cause:** Unprinted escape sequences

**Diagnosis:**
```bash
# Show escape sequences
TERMISU_LOG_LEVEL=trace crystal run demo.cr 2>&1 | grep '\\e'
```

**Solution:** Check terminfo capabilities, use fallback sequences.

### Events Not Received

**Symptom:** Keyboard/mouse not working

**Diagnosis:**
```crystal
# Check raw mode
puts "Raw mode: #{termisu.raw_mode?}"  # Should be true

# Check if event loop is running
# Add logging in loop
```

**Solution:** Ensure terminal is in raw mode, event loop is running.

### Terminal Not Restored on Exit

**Symptom:** Terminal behaves weirdly after app exits

**Cause:** Missing `ensure` block

**Solution:**
```crystal
termisu = Termisu.new
begin
  # ... app logic ...
ensure
  termisu.close  # ALWAYS
end
```

### Laggy Rendering

**Symptom:** Low frame rate

**Diagnosis:**
```crystal
# Profile render time
start = Time.monotonic
termisu.render
puts "Render: #{(Time.monotonic - start).total_milliseconds}ms"
```

**Solution:** Batch cell changes, minimize color changes.

## Debugging Tools

### strace (Linux)

```bash
# See system calls
strace -f -e trace=read,write crystal run examples/demo.cr

# Filter by terminal fd
strace -f -e trace=read,write crystal run demo.cr 2>&1 | grep '/dev/tty'
```

### dtruss (macOS)

```bash
# System call tracing
sudo dtruss -t read,write crystal run demo.cr
```

### ltrace (Linux)

```bash
# Library call tracing
ltrace crystal run demo.cr
```

## Unit Testing Debuggable Code

```crystal
# Test with capture
it "renders correct output" do
  output = IO::Memory.new
  renderer = RenderState.new(output)

  buffer.set_cell(0, 0, 'X', fg: Color.red)
  buffer.render_to(renderer)

  output.to_s.should contain("\e[31m")
  output.to_s.should contain("X")
end
```

## Quick Reference

| Issue | Debug Command |
|-------|---------------|
| Logging | `TERMISU_LOG_LEVEL=debug crystal run demo.cr` |
| View logs | `tail -f /tmp/termisu.log` |
| Show input bytes | Create DebugReader |
| Check terminal state | `puts termisu.raw_mode?` |
| Memory leak | `valgrind --leak-check=full ./demo` |
| Profile render | `Benchmark.measure { termisu.render }` |
| System calls | `strace -f crystal run demo.cr` |
| Broken terminal | `reset` or `tput reset` |

## Best Practices

1. **Use logging** - Enable debug logs early
2. **Test recovery** - Kill -9 your app, verify terminal works
3. **Profile first** - Measure before optimizing
4. **Add debug output** - Printf/puts for quick checks
5. **Test on real terminals** - Not just in CI
6. **Check modes** - Verify raw/alternate screen state
7. **Use ensure blocks** - Always cleanup
