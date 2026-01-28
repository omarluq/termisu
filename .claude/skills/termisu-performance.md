# Termisu Performance & Optimization

Performance profiling, benchmarking, and optimization techniques for Termisu TUI applications.

## When to Use

- "Optimize rendering"
- "Reduce lag"
- "Profile performance"
- "Benchmark code"
- "Frame rate issues"
- "Memory leak"

## Quick Commands

```bash
# Release mode benchmarks
bin/hace bench          # Full benchmarks
bin/hace bench-quick    # Quick compile, less accurate

# Profiling (Linux)
bin/hace perf           # CPU profiling with perf
bin/hace callgrind      # Call graph profiling
bin/hace memcheck       # Memory leak detection (valgrind)
```

## Performance Targets

| Metric | Target | Why |
|--------|--------|-----|
| Frame time | < 16ms | 60 FPS smooth animation |
| Render time | < 10ms | Leaves 6ms for logic |
| Memory growth | 0 MB/minute | No leaks |
| Startup time | < 100ms | Fast app launch |

## Profiling Workflow

### 1. Identify Bottleneck

```bash
# CPU profiling
bin/hace perf

# View report
perf report
```

### 2. Measure Before Optimizing

```crystal
require "benchmark"

# Measure render time
time = Benchmark.measure do
  termisu.render
end

puts "Render: #{time.total_milliseconds}ms"

# Target: < 16ms for 60 FPS
if time.total_milliseconds > 16
  puts "WARNING: Frame too slow!"
end
```

### 3. Optimize Hot Path

Common bottlenecks:
- Too many render calls
- Redundant color changes
- String allocations in loops
- Inefficient diff algorithm

### 4. Verify Improvement

```bash
# Run before/after benchmarks
bin/hace bench > before.txt
# ... make changes ...
bin/hace bench > after.txt
diff before.txt after.txt
```

## Rendering Optimization

### Batch Cell Changes

**BAD:**
```crystal
100.times do |i|
  termisu.set_cell(i, 0, 'X', fg: Color.red)
  termisu.render  # 100 renders!
end
```

**GOOD:**
```crystal
100.times do |i|
  termisu.set_cell(i, 0, 'X', fg: Color.red)
end
termisu.render  # Single render
```

### Minimize Color Changes

**BAD:**
```crystal
# Alternates colors every cell
["R", "G", "B"].cycle.first(100).each_with_index do |c, i|
  color = c == "R" ? Color.red : c == "G" ? Color.green : Color.blue
  termisu.set_cell(i, 0, 'X', fg: color)
end
```

**GOOD:**
```crystal
# Group by color
(0...33).each { |i| termisu.set_cell(i, 0, 'X', fg: Color.red) }
(33...66).each { |i| termisu.set_cell(i, 0, 'X', fg: Color.green) }
(66...100).each { |i| termisu.set_cell(i, 0, 'X', fg: Color.blue) }
termisu.render
```

### Skip Unchanged Cells

```crystal
@dirty = false

def update_cell(x, y, char, fg = nil, bg = nil)
  current = termisu.get_cell(x, y)
  return if current && current.char == char && current.foreground == fg

  termisu.set_cell(x, y, char, fg: fg, bg: bg)
  @dirty = true
end

# Only render if something changed
termisu.render if @dirty
```

### Use Partial Updates

```crystal
# Instead of clearing entire screen
termisu.clear

# Just update changed region
@dirty_regions.each do |x, y, w, h|
  (y...(y+h)).each do |row|
    (x...(x+w)).each do |col|
      termisu.set_cell(col, row, ' ')
    end
  end
end
```

## Animation Optimization

### Adaptive Frame Rate

```crystal
@target_fps = 60
@actual_fps = 0.0
@last_frame = Time.instant

when Termisu::Event::Tick
  now = Time.instant
  delta = now - @last_frame
  @last_frame = now

  @actual_fps = 1.0 / delta.total_seconds if delta.total_seconds > 0

  # Auto-adjust based on performance
  if @actual_fps < @target_fps * 0.9
    @target_fps = (@target_fps * 0.9).to_i.clamp(15, 60)
  end

  update_and_render
end
```

### Skip Idle Frames

```crystal
@idle_seconds = 0
@last_activity = Time.instant

when Termisu::Event::Key, Termisu::Event::Mouse
  @last_activity = Time.instant
  @idle_seconds = 0

when Termisu::Event::Tick
  @idle_seconds = (Time.instant - @last_activity).total_seconds

  if @idle_seconds > 5
    # Reduce FPS when idle (15 FPS instead of 60)
    next if (@frame % 4) != 0
  end

  render
end
```

### Use System Timer for Smooth Animation

```crystal
# For smooth 60 FPS+
termisu.enable_system_timer(16.milliseconds)

# Sleep timer is less precise
# termisu.enable_timer(16.milliseconds)  # Only ~48 FPS reliable
```

## Memory Optimization

### Reuse Strings

**BAD:**
```crystal
loop do
  text = "Hello, World!"  # Allocates new string each iteration
  draw_text(0, 0, text)
end
```

**GOOD:**
```crystal
HELLO = "Hello, World!"  # Allocate once

loop do
  draw_text(0, 0, HELLO)
end
```

### Reuse Color Objects

```crystal
# Pre-allocate colors
RED = Color.red
GREEN = Color.green
BLUE = Color.blue

# Use in loop
termisu.set_cell(x, y, 'X', fg: RED)
```

### Avoid Unnecessary Buffers

```crystal
# BAD: Creates new array each frame
cells = (0...width).map { |x| get_cell(x, y) }

# GOOD: Iterate directly
width.times do |x|
  cell = get_cell(x, y)
  # ...
end
```

## String Optimization

### Use Char Instead of String

```crystal
# BAD: String comparison
if cell.char == "X"
  # ...
end

# GOOD: Char comparison
if cell.char == 'X'
  # ...
end
```

### Avoid String Concatenation in Loops

**BAD:**
```crystal
result = ""
100.times do |i|
  result += i.to_s  # Allocates new string each time
end
```

**GOOD:**
```crystal
result = String::Builder.new
100.times do |i|
  result << i
end
result = result.to_s
```

### Use StringIO for Building Output

```crystal
output = IO::Memory.new

output << "\e[" << x << ';' << y << 'H'
output << text

result = output.to_s
```

## Event Loop Optimization

### Reduce Poll Timeout

```crystal
# BAD: Too slow, feels laggy
event = termisu.poll_event(100)  # 100ms timeout

# GOOD: Responsive
event = termisu.poll_event(10)   # 10ms timeout

# BEST: Use non-blocking for maximum responsiveness
event = termisu.try_poll_event
```

### Use Non-Blocking Poll for Idle Rendering

```crystal
loop do
  if event = termisu.try_poll_event
    handle_event(event)
  end

  # Always render, even without events
  update_animation
  termisu.render
end
```

## Memory Leak Detection

```bash
# Valgrind memcheck
bin/hace memcheck

# Look for:
# - "definitely lost": memory leaks
# - "still reachable": might be OK (globals)
# - "invalid read/write": use-after-free bugs
```

### Common Leak Sources

1. **Fiber not stopped**
   ```crystal
   # BAD: Fiber never stops
   spawn { loop { sleep 1 } }

   # GOOD: Stop fiber
   @running = true
   @fiber = spawn { while @running; sleep 1; end }
   # Later: @running = false; @fiber.join
   ```

2. **Channel not closed**
   ```crystal
   # BAD: Channel never closed
   @channel = Channel(T).new

   # GOOD: Close when done
   @channel.close
   ```

3. **Event source not stopped**
   ```crystal
   # BAD: Source keeps running
   source.start(channel)

   # GOOD: Stop in ensure
   begin
     source.start(channel)
     # ...
   ensure
     source.stop
   end
   ```

## Benchmarking Patterns

### Simple Benchmark

```crystal
require "benchmark"

# Compare two approaches
Benchmark.bm do |x|
  x.report("approach 1:") do
    10000.times { approach_1 }
  end

  x.report("approach 2:") do
    10000.times { approach_2 }
  end
end

# Output:
#                user     system      total        real
# approach 1:  0.010000   0.000000   0.010000 (  0.010412)
# approach 2:  0.005000   0.000000   0.005000 (  0.005201)
```

### Memory Benchmark

```crystal
# Measure memory usage
GC.collect
before = `ps -o rss= -p #{Process.pid}`.to_i

# ... run code ...

GC.collect
after = `ps -o rss= -p #{Process.pid}`.to_i

puts "Memory: #{after - before} KB"
```

## Performance Debugging

### Count Changed Cells

```crystal
# Track how many cells change per frame
@changed_count = 0

def set_cell_tracked(x, y, char, fg = nil, bg = nil)
  @changed_count += 1
  termisu.set_cell(x, y, char, fg: fg, bg: bg)
end

# After render
puts "Changed: #{@changed_count} / #{width * height} cells"
```

### Measure Render Time

```crystal
render_times = [] of Time::Span

loop do
  start = Time.instant
  termisu.render
  elapsed = Time.instant - start

  render_times << elapsed

  if render_times.size > 60
    avg = render_times.sum / render_times.size
    puts "Avg render: #{avg.total_milliseconds}ms"
    render_times.clear
  end
end
```

## Cross-Platform Considerations

### Linux: Best Profiling

```bash
# perf for CPU
bin/hace perf

# valgrind for memory
bin/hace memcheck
```

### macOS: Limited Profiling

```bash
# Instruments app (GUI)
# Or: sample command
sample pid 10  # Sample for 10 seconds
```

### Release Builds

```bash
# Always benchmark in release mode
crystal build --release examples/demo.cr -o demo
./demo
```

## Quick Reference

| Issue | Solution |
|-------|----------|
| Slow rendering | Batch cell changes, minimize color changes |
| Low FPS | Use system_timer, reduce render work |
| Memory leak | Stop fibers/sources in ensure blocks |
| Laggy input | Reduce poll timeout, use non-blocking |
| High CPU | Skip idle frames, adaptive FPS |

## Best Practices

1. **Profile first** - Measure before optimizing
2. **Batch operations** - Minimize render calls
3. **Reuse objects** - Avoid allocations in loops
4. **Use release builds** - Profile with `--release`
5. **Stop async resources** - Fibers, channels, sources
6. **Adaptive quality** - Reduce FPS when idle
7. **Test on real terminals** - CI may not catch perf issues
