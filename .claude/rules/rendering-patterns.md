# Rendering Patterns

Double-buffering, cell-based rendering patterns for Termisu TUI development.

## When to Use

- "Draw text to screen"
- "Optimize rendering"
- "Reduce flicker"
- "Batch draw calls"
- "Handle colors efficiently"

## Core Rendering Pipeline

```
User Code (set_cell)
       ↓
Back Buffer (modifications)
       ↓
render() - Diff front vs back
       ↓
RenderState (escape seq optimization)
       ↓
Terminal (TTY write)
```

## Basic Rendering Pattern

```crystal
termisu = Termisu.new

begin
  # Set cells (writes to back buffer)
  termisu.set_cell(0, 0, 'H', fg: Termisu::Color.green)
  termisu.set_cell(1, 0, 'e', fg: Termisu::Color.green)
  termisu.set_cell(2, 0, 'l', fg: Termisu::Color.green)
  termisu.set_cell(3, 0, 'l', fg: Termisu::Color.green)
  termisu.set_cell(4, 0, 'o', fg: Termisu::Color.green)

  # Render changes (diff-based, only changed cells)
  termisu.render

  # Wait for input
  termisu.wait_for_input(5000)
ensure
  termisu.close
end
```

## Double Buffering

**Concept:** Two buffers - front (what's displayed) and back (what you're drawing).

```crystal
# First draw
termisu.set_cell(10, 5, 'A', fg: Color.red)
termisu.render  # 'A' appears on screen (back → front)

# Second draw - same cell
termisu.set_cell(10, 5, 'A', fg: Color.red)
termisu.render  # Nothing! Cell unchanged, skipped

# Third draw - different cell
termisu.set_cell(10, 5, 'B', fg: Color.red)
termisu.render  # Only 'B' update sent to terminal
```

**Benefits:**
- Minimal escape sequences
- Reduced bandwidth
- Faster rendering
- No flicker

## Cell Manipulation

### Basic Cell Setting

```crystal
# Single cell
termisu.set_cell(x, y, 'X')

# With foreground color
termisu.set_cell(x, y, 'X', fg: Color.red)

# With background color
termisu.set_cell(x, y, 'X', fg: Color.red, bg: Color.blue)

# With text attribute
termisu.set_cell(x, y, 'X', attr: Attribute::Bold)

# All options
termisu.set_cell(x, y, 'X', fg: Color.red, bg: Color.blue, attr: Attribute::Bold | Attribute::Underline)
```

### Reading Cell Contents

```crystal
# Note: This accesses back buffer (what you set, not what's displayed)
cell = termisu.get_cell(x, y)
if cell
  char = cell.char
  fg = cell.foreground
  bg = cell.background
  attr = cell.attribute
end
```

## Text Drawing Patterns

### Simple Text Helper

```crystal
# Reusable drawing function
draw_text = ->(x : Int32, y : Int32, text : String, fg : Color, bg : Color? = nil) do
  text.each_char_with_index do |char, idx|
    termisu.set_cell(x + idx, y, char, fg: fg, bg: bg)
  end
end

# Usage
draw_text.call(10, 5, "Hello, World!", Color.green)
```

### Centered Text

```crystal
def draw_centered(text : String, y : Int32, fg : Color, bg : Color? = nil)
  width = termisu.size[0]
  start_x = [(width - text.size) // 2, 0].max
  draw_text.call(start_x, y, text, fg, bg)
end

draw_centered("Press any key to continue", 10, Color.white)
```

### Multi-line Text

```crystal
def draw_multiline(x : Int32, y : Int32, lines : Array(String), fg : Color, bg : Color? = nil)
  lines.each_with_index do |line, idx|
    draw_text.call(x, y + idx, line, fg, bg)
  end
end

draw_multiline(5, 5, ["Line 1", "Line 2", "Line 3"], Color.cyan)
```

### Box Drawing

```crystal
# Unicode box characters
BOX_CHARS = {
  tl: '┌', tr: '┐', bl: '└', br: '┘',
  h:  '─', v:  '│',
}

def draw_box(x : Int32, y : Int32, width : Int32, height : Int32, fg : Color, bg : Color? = nil)
  # Corners
  termisu.set_cell(x, y, BOX_CHARS[:tl], fg: fg, bg: bg)
  termisu.set_cell(x + width - 1, y, BOX_CHARS[:tr], fg: fg, bg: bg)
  termisu.set_cell(x, y + height - 1, BOX_CHARS[:bl], fg: fg, bg: bg)
  termisu.set_cell(x + width - 1, y + height - 1, BOX_CHARS[:br], fg: fg, bg: bg)

  # Horizontal edges
  (x + 1...x + width - 1).each do |i|
    termisu.set_cell(i, y, BOX_CHARS[:h], fg: fg, bg: bg)
    termisu.set_cell(i, y + height - 1, BOX_CHARS[:h], fg: fg, bg: bg)
  end

  # Vertical edges
  (y + 1...y + height - 1).each do |j|
    termisu.set_cell(x, j, BOX_CHARS[:v], fg: fg, bg: bg)
    termisu.set_cell(x + width - 1, j, BOX_CHARS[:v], fg: fg, bg: bg)
  end
end

draw_box(5, 3, 40, 10, Color.white, Color.blue)
```

## Rendering Optimization

### Batch Changes

```crystal
# BAD: Renders on each change
10.times do |i|
  termisu.set_cell(i, 0, 'X', fg: Color.red)
  termisu.render  # Too many renders!
end

# GOOD: Render once after all changes
10.times do |i|
  termisu.set_cell(i, 0, 'X', fg: Color.red)
end
termisu.render  # Single render
```

### Partial Redraws

```crystal
# Only update specific region, not entire screen
@dirty_regions = [] of Tuple(Int32, Int32, Int32, Int32)  # x, y, w, h

def invalidate(x : Int32, y : Int32, width : Int32, height : Int32)
  @dirty_regions << {x, y, width, height}
end

# Mark region for update
invalidate(10, 5, 20, 3)

# Later, only redraw dirty regions
# (Note: Termisu doesn't support partial redraws natively yet,
# but you can optimize by avoiding unchanged cells)
```

### Minimize Color Changes

```crystal
# BAD: Alternates colors every cell
["R", "G", "B"].each_with_index do |c, i|
  color = c == "R" ? Color.red : c == "G" ? Color.green : Color.blue
  termisu.set_cell(i, 0, 'X', fg: color)
end

# GOOD: Group by color
draw_text.call(0, 0, "RRRRR", Color.red)
draw_text.call(5, 0, "GGGGG", Color.green)
draw_text.call(10, 0, "BBBBB", Color.blue)
```

### Skip Redraws When Unchanged

```crystal
@dirty = false

def update_cell(x, y, char, fg = nil, bg = nil, attr = nil)
  current = termisu.get_cell(x, y)
  return if current && current.char == char && current.foreground == fg

  termisu.set_cell(x, y, char, fg: fg, bg: bg, attr: attr)
  @dirty = true
end

# Only render if something changed
update_cell(10, 10, 'X', Color.red)
termisu.render if @dirty
```

## Clearing and Syncing

### Clear Screen

```crystal
# Clear entire buffer
termisu.clear

# Clear then render
termisu.clear
termisu.render  # Screen is now empty
```

### Sync (Full Redraw)

```crystal
# sync forces full redraw, ignoring diff optimization
termisu.sync

# Use cases:
# 1. After terminal resize
# 2. After switching terminal modes
# 3. After external program corrupted screen
# 4. When you know everything changed

when Termisu::Event::Resize
  termisu.sync  # Always sync on resize
end
```

### Cursor Management

```crystal
# Move cursor
termisu.set_cursor(10, 5)

# Hide cursor (for pure TUI)
termisu.hide_cursor

# Show cursor (for input fields)
termisu.show_cursor

# Save cursor position (ANSI)
# Termisu handles this automatically during render,
# but you can use explicit cursor if needed
```

## Color Patterns

### Gradients

```crystal
def draw_gradient(y : Int32)
  width = termisu.size[0]

  width.times do |x|
    # RGB gradient from blue to red
    r = (255 * x / width).to_i
    g = 0
    b = (255 * (width - x) / width).to_i
    color = Color.rgb(r, g, b)
    termisu.set_cell(x, y, '█', fg: color)
  end
end

draw_gradient(5)
termisu.render
```

### Color Palette Display

```crystal
def show_palette
  # ANSI-8 colors
  [:black, :red, :green, :yellow, :blue, :magenta, :cyan, :white].each_with_index do |name, i|
    color = Color.from_name(name)
    termisu.set_cell(i * 2, 0, '█', fg: color)
  end

  # ANSI-256 colors (16-231 are 6x6x6 color cube)
  (0...216).each do |i|
    x = (i % 36) * 2
    y = 2 + (i // 36)
    r = (i / 36) * 51
    g = ((i / 6) % 6) * 51
    b = (i % 6) * 51
    color = Color.rgb(r, g, b)
    termisu.set_cell(x, y, '█', fg: color)
  end

  # Grayscale (232-255)
  (0...24).each do |i|
    level = (i * 10).to_i + 8
    color = Color.grayscale(level)
    termisu.set_cell(i * 2, 10, '█', fg: color)
  end

  termisu.render
end
```

## Animation Patterns

### Frame-Based Animation

```crystal
@frame = 0

def draw_spinner(y : Int32)
  chars = ['|', '/', '-', '\\']
  char = chars[@frame % chars.size]
  termisu.set_cell(0, y, char, fg: Color.cyan)
end

# In event loop
when Termisu::Event::Tick
  @frame += 1
  draw_spinner(0)
  termisu.render
end
```

### Double-Buffered Animation

```crystal
# Termisu handles double buffering automatically,
# but for complex scenes, use offscreen buffer pattern:

class Scene
  @width : Int32
  @height : Int32
  @cells : Array(Array(Cell))

  def initialize(@width, @height)
    @cells = Array.new(@height) { Array.new(@width) { Cell.new(' ') } }
  end

  def set_cell(x, y, char, fg = nil, bg = nil, attr = nil)
    return if x < 0 || x >= @width || y < 0 || y >= @height
    @cells[y][x] = Cell.new(char, fg, bg, attr)
  end

  def render_to(termisu : Termisu)
    @height.times do |y|
      @width.times do |x|
        cell = @cells[y][x]
        termisu.set_cell(x, y, cell.char, fg: cell.fg, bg: cell.bg, attr: cell.attr)
      end
    end
  end
end

# Usage
scene = Scene.new(40, 10)
scene.set_cell(10, 5, '@', fg: Color.yellow)
scene.render_to(termisu)
termisu.render
```

## Text Attributes

### Attribute Combinations

```crystal
# Single attribute
termisu.set_cell(0, 0, 'A', attr: Attribute::Bold)

# Combined attributes (bitwise OR)
combined = Attribute::Bold | Attribute::Underline | Attribute::Blink
termisu.set_cell(1, 0, 'B', attr: combined)

# All available attributes
attrs = [
  Attribute::Bold,
  Attribute::Dim,
  Attribute::Italic,
  Attribute::Underline,
  Attribute::Blink,
  Attribute::Reverse,
  Attribute::Hidden,
  Attribute::Strikethrough,
]

attrs.each_with_index do |attr, i|
  termisu.set_cell(i * 2, 0, 'A', attr: attr)
end
```

## Performance Monitoring

### Count Changed Cells

```crystal
# Manually track changes for debugging
@changed_cells = 0

def set_cell_tracked(x, y, char, fg = nil, bg = nil, attr = nil)
  @changed_cells += 1
  termisu.set_cell(x, y, char, fg: fg, bg: bg, attr: attr)
end

# Before render
puts "Changed cells: #{@changed_cells}"
termisu.render
@changed_cells = 0
```

### Measure Render Time

```crystal
require "benchmark"

start = Time.monotonic
termisu.render
elapsed = Time.monotonic - start

puts "Render time: #{elapsed.total_milliseconds}ms"

# Target: < 16ms for 60 FPS
if elapsed.total_milliseconds > 16
  puts "WARNING: Frame too slow!"
end
```

## Quick Reference

| Task | Code |
|------|------|
| Set cell | `termisu.set_cell(x, y, 'X')` |
| Set with colors | `termisu.set_cell(x, y, 'X', fg: Color.red, bg: Color.blue)` |
| Set with attribute | `termisu.set_cell(x, y, 'X', attr: Attribute::Bold)` |
| Get cell | `termisu.get_cell(x, y)` |
| Clear screen | `termisu.clear` |
| Render | `termisu.render` |
| Full redraw | `termisu.sync` |
| Cursor position | `termisu.set_cursor(x, y)` |
| Hide cursor | `termisu.hide_cursor` |
| Show cursor | `termisu.show_cursor` |
| Terminal size | `termisu.size` |

## Best Practices

1. **Batch changes** - Call `set_cell` multiple times, then `render` once
2. **Use helpers** - Create functions for common drawing operations
3. **Group by color** - Minimize color changes for better performance
4. **Sync on resize** - Always call `termisu.sync` after resize events
5. **Hide cursor** - For pure TUI, hide cursor to avoid flicker
6. **Profile renders** - Keep under 16ms for smooth 60 FPS
7. **Use double buffering** - Let Termisu's diff algorithm optimize
8. **Avoid redundant sets** - Check if cell already has desired value
9. **Use Unicode** - Take advantage of box drawing and block chars
10. **Test on small terminals** - Ensure layout works at 80x24
