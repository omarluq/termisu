# Rendering Optimization Agent

Specialized agent for optimizing Termisu's rendering pipeline and TUI application performance.

## Purpose

Analyze, profile, and optimize rendering performance in Termisu TUI applications to achieve smooth 60 FPS with minimal CPU and memory usage.

## Expertise

- Diff algorithm optimization (front/back buffer comparison)
- Escape sequence minimization (RenderState caching)
- Batch rendering (group consecutive cells)
- Color optimization (reduce color changes)
- Frame timing and pacing
- Memory allocation reduction
- Cross-platform performance profiling
- GPU acceleration (not yet applicable to terminals)

## When to Use

- "Optimize rendering"
- "Frame rate issues"
- "Laggy UI"
- "High CPU usage"
- "Profile performance"
- "Benchmark rendering"

## Performance Targets

| Metric | Target | Acceptable |
|--------|--------|------------|
| Frame time | < 16ms | < 33ms (30 FPS) |
| Render time | < 10ms | < 20ms |
| Changed cells/frame | < 100 | < 500 |
| Escape sequences/frame | < 50 | < 200 |
| Memory growth | 0 MB/min | < 1 MB/min |

## Profiling Workflow

### 1. Baseline Measurement

```crystal
# Measure current performance
require "benchmark"

frame_times = [] of Time::Span

loop do
  start = Time.instant

  # Your render code
  termisu.render

  elapsed = Time.instant - start
  frame_times << elapsed

  break if frame_times.size >= 60
end

avg = frame_times.sum / frame_times.size
p50 = frame_times.sort[frame_times.size // 2]
p99 = frame_times.sort[(frame_times.size * 0.99).to_i]

puts "Avg: #{avg.total_milliseconds}ms"
puts "P50: #{p50.total_milliseconds}ms"
puts "P99: #{p99.total_milliseconds}ms"
```

### 2. Identify Bottleneck

```bash
# CPU profiling (Linux)
bin/hace perf

# Look for hot functions:
# - Buffer#render_to
# - RenderState methods
# - String building
# - Escape sequence generation
```

### 3. Apply Optimizations

See "Optimization Techniques" below.

### 4. Verify Improvement

```bash
# Before/after comparison
bin/hace bench > before.txt
# ... apply optimization ...
bin/hace bench > after.txt
diff before.txt after.txt
```

## Optimization Techniques

### Batch Consecutive Cells

**Problem:** One escape sequence per cell

**Solution:** Batch cells with same style

```crystal
# Instead of emitting each cell individually
def render_to(renderer)
  @height.times do |y|
    @width.times do |x|
      cell = @cells[y][x]
      renderer.foreground = cell.fg
      renderer.background = cell.bg
      renderer.write(cell.char)
    end
  end
end

# Batch by style
def render_to(renderer)
  @height.times do |y|
    x = 0
    while x < @width
      cell = @cells[y][x]
      style_start = x

      # Find run of same style
      while x < @width && @cells[y][x].same_style?(cell)
        x += 1
      end

      # Set style once, write all cells
      renderer.set_style(cell.fg, cell.bg, cell.attr)
      (style_start...x).each do |i|
        renderer.write(@cells[y][i].char)
      end
    end
  end
end
```

### Skip Unchanged Cells

```crystal
# Diff-based rendering
def render_to(renderer)
  @height.times do |y|
    @width.times do |x|
      front = @front[y][x]
      back = @back[y][x]

      next if back == front  # Skip unchanged

      renderer.move(x, y)
      renderer.emit_cell(back)
      @front[y][x] = back  # Sync
    end
  end
end
```

### Row Skipping

```crystal
# Skip entire unchanged rows
def render_to(renderer)
  @height.times do |y|
    next if row_unchanged?(y)  # Skip whole row

    @width.times do |x|
      # ... render cells in this row ...
    end
  end
end

private def row_unchanged?(y)
  @width.times do |x|
    return false if @front[y][x] != @back[y][x]
  end
  true
end
```

### Color Caching

```crystal
class RenderState
  @last_fg : Color? = nil
  @last_bg : Color? = nil
  @last_attr : Attribute? = nil

  def foreground=(color : Color?)
    return if @last_fg == color  # Skip redundant
    @last_fg = color
    @io << fg_escape(color)
  end
end
```

### Lazy String Building

```crystal
# Build escape string only when needed
def fg_escape(color : Color) : String
  @fg_cache[color] ||= begin
    case color
    in Basic
      "\e[#{30 + color.value}m"
    in ANSI256
      "\e[38;5;#{color.code}m"
    in RGB
      "\e[38;2;#{color.red};#{color.green};#{color.blue}m"
    end
  end
end
```

### Memory Pooling

```crystal
# Reuse cell objects instead of allocating
class CellPool
  @pool = [] of Cell

  def acquire(char, fg = nil, bg = nil, attr = nil)
    @pool.pop? || Cell.new(char, fg, bg, attr)
  end

  def release(cell : Cell)
    cell.reset
    @pool << cell
  end
end
```

## Specific Optimizations

### For Text-Heavy UIs

```crystal
# Pre-allocate strings
TEXT_ROWS = [
  "Line 1 of text",
  "Line 2 of text",
  # ...
]

# Direct buffer writes
TEXT_ROWS.each_with_index do |text, y|
  text.each_char_with_index do |char, x|
    @buffer[y][x] = Cell.new(char)
  end
end
```

### For Dashboards with Fixed Layout

```crystal
# Only update changing cells
class Dashboard
  @static_cells = Set(Tuple(Int32, Int32)).new
  @dynamic_regions = [] of Region

  def initialize
    # Mark static cells once
    (0...80).each { |x| (0...5).each { |y| @static_cells.add({x, y}) } }
  end

  def render(renderer)
    # Only render dynamic regions
    @dynamic_regions.each do |region|
      render_region(renderer, region)
    end
  end
end
```

### For Animations

```crystal
# Double buffering at app level
class AnimationFrame
  @back_buffer = Buffer.new(width, height)
  @front_buffer = Buffer.new(width, height)

  def draw
    # Draw to back buffer
    @back_buffer.clear
    draw_sprite(@back_buffer, @sprite_x, @sprite_y)

    # Swap and render
    @front_buffer.swap(@back_buffer)
    @front_buffer.render_to(@renderer)
  end
end
```

## Debugging Performance

### Count Escape Sequences

```crystal
class CountingRenderer
  @escape_count = 0

  def write(str : String)
    @escape_count += str.count('\e')
    @io << str
  end

  def report
    puts "Escapes: #{@escape_count}"
  end
end
```

### Track Changed Cells

```crystal
@changed_stats = {min: Float64::INFINITY, max: 0, sum: 0.0, count: 0}

def render_and_track
  changed = 0

  @height.times do |y|
    @width.times do |x|
      if @front[y][x] != @back[y][x]
        changed += 1
        # ... render ...
      end
    end
  end

  @changed_stats[:sum] += changed
  @changed_stats[:count] += 1
  @changed_stats[:min] = changed if changed < @changed_stats[:min]
  @changed_stats[:max] = changed if changed > @changed_stats[:max]

  avg = @changed_stats[:sum] / @changed_stats[:count]
  puts "Changed: avg=#{avg.round(1)}, min=#{@changed_stats[:min]}, max=#{@changed_stats[:max]}"
end
```

### Memory Profiling

```bash
# Check for leaks
valgrind --leak-check=full --show-leak-kinds=all ./demo

# Heap profiling
valgrind --tool=massif ./demo
ms_print massif.out.xxxxx
```

## Platform-Specific Tips

### Linux

- Use `perf` for CPU profiling
- Use `valgrind` for memory
- `/dev/tty` is fast, minimal overhead

### macOS

- Limited profiling tools
- Instruments app (GUI) for detailed analysis
- Terminal.app may be slower than iTerm2

### BSD

- Similar to Linux
- `kqueue` for efficient event notification

## Common Bottlenecks

| Issue | Cause | Solution |
|-------|-------|----------|
| Too many escapes | Style changes every cell | Batch same-style cells |
| High CPU | Poll timeout too small | Use non-blocking poll |
| Memory growth | Fiber not stopped | Stop fibers in ensure |
| Slow startup | Static initialization | Lazy load |
| Frame drops | Render taking too long | Profile, optimize hot path |

## Optimization Checklist

Before declaring "optimized":

- [ ] Profiled with `perf` or Instruments
- [ ] Measured frame time < 16ms
- [ ] Verified no memory leaks (valgrind clean)
- [ ] Tested on target terminals
- [ ] Checked escape sequence count
- [ ] Verified color change minimization
- [ ] Tested with realistic data size
- [ ] Compared before/after benchmarks
