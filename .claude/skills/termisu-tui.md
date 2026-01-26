# Termisu TUI Development

Terminal UI patterns and idioms for Termisu development.

## When to Use

- "Create a TUI app"
- "Terminal input handling"
- "Event loop pattern"
- "Animation in terminal"
- "Color rendering"

## Core Patterns

### 1. Basic Initialization

```crystal
require "termisu"

termisu = Termisu.new

begin
  # TUI logic here
ensure
  termisu.close  # Always cleanup
end
```

**Critical:** The `ensure` block pattern is critical for proper terminal restoration.

### 2. Event Loop Pattern

**Manual polling:**
```crystal
loop do
  if event = termisu.poll_event(50)  # 50ms timeout
    case event
    when Termisu::Event::Key
      break if event.key.escape?
    when Termisu::Event::Resize
      termisu.sync  # Full redraw on resize
    when Termisu::Event::Tick
      # Animation frame
    end
  end
  termisu.render
end
```

**Iterator-based:**
```crystal
termisu.each_event do |event|
  case event
  when Termisu::Event::Key
    break if event.key.escape?
  when Termisu::Event::Tick
    # Animation frame
  end
  termisu.render
end
```

### 3. Animation with Timers

```crystal
# Enable timer for ~60 FPS (sleep-based)
termisu.enable_timer(16.milliseconds)

# OR: Kernel-level timer (more precise)
termisu.enable_system_timer(16.milliseconds)

# Handle tick events
when Termisu::Event::Tick
  @frame += 1
  delta_ms = event.delta.total_milliseconds
  missed = event.missed_ticks

  # Update physics/rendering
  render_frame(current_fps, delta_ms, missed)
end
```

**Timer Comparison:**
| Feature | Timer (sleep) | SystemTimer (kernel) |
|---------|---------------|---------------------|
| Mechanism | `sleep` in fiber | timerfd/epoll (Linux), kqueue (macOS) |
| Precision | ~1-2ms jitter | Sub-millisecond |
| Max FPS | ~48 FPS reliable | ~90 FPS reliable |
| Missed tick detection | No | Yes (`event.missed_ticks`) |

### 4. Terminal Mode Switching

**Shell-out (recommended):**
```crystal
termisu.suspend do
  # Exits alternate screen, enables cooked mode
  system("vim file.txt")
end
# TUI fully restored
```

**Password input:**
```crystal
password = termisu.with_password_mode do
  print "Password: "
  gets.try(&.chomp)
end
```

**Custom modes:**
```crystal
termisu.with_mode(Termisu::Terminal::Mode.semi_raw) do
  # Char-by-char with signals (Ctrl+C works)
end

termisu.with_cbreak_mode(preserve_screen: false) do
  # Char-by-char with echo
end
```

### 5. Enhanced Keyboard Input

```crystal
termisu.enable_enhanced_keyboard

# Distinguish Tab vs Ctrl+I
case event.key
when .tab?
  # Definitely Tab, not Ctrl+I
end
```

### 6. Mouse Handling

```crystal
termisu.enable_mouse

when Termisu::Event::Mouse
  mouse_x = event.x
  mouse_y = event.y

  if event.wheel?
    # Scroll wheel event
  elsif event.press?
    # Button press
  elsif event.motion?
    # Drag event
  end
end
```

### 7. Color System

```crystal
# ANSI-8 basic colors
termisu.set_cell(x, y, 'A', fg: Termisu::Color.red)

# ANSI-256 palette
color = Termisu::Color.ansi256(172)
termisu.set_cell(x, y, 'B', fg: color)

# Grayscale (24 levels)
color = Termisu::Color.grayscale(level)  # 0-23

# RGB truecolor
color = Termisu::Color.rgb(255, 128, 64)
termisu.set_cell(x, y, 'C', fg: color)

# Hex color
color = Termisu::Color.from_hex("#FF5733")

# Color conversions
rgb_color = Termisu::Color.rgb(255, 128, 64)
ansi256 = rgb_color.to_ansi256
ansi8 = rgb_color.to_ansi8
```

### 8. Text Attributes

```crystal
# Single attributes
termisu.set_cell(x, y, 'A', attr: Termisu::Attribute::Bold)

# Combined attributes (bitwise OR)
combined = Termisu::Attribute::Bold | Termisu::Attribute::Underline
termisu.set_cell(x, y, 'B', attr: combined)
```

**Available attributes:**
- `Bold`, `Dim`, `Italic`/`Cursive`
- `Underline`, `Blink`, `Reverse`
- `Hidden`, `Strikethrough`

### 9. Drawing Helper Pattern

```crystal
# Reusable drawing function
draw_text = ->(x : Int32, y : Int32, text : String, fg : Termisu::Color, bg : Termisu::Color?) do
  text.each_char_with_index do |char, idx|
    if bg
      termisu.set_cell(x + idx, y, char, fg: fg, bg: bg)
    else
      termisu.set_cell(x + idx, y, char, fg: fg)
    end
  end
end

# Usage
draw_text.call(10, 5, "Hello", Termisu::Color.green, nil)
```

## API Reference

### Terminal Operations

```crystal
termisu.size                  # => {width, height}
termisu.alternate_screen?     # => true/false
termisu.raw_mode?             # => true/false
termisu.current_mode          # => Mode flags or nil
```

### Cell Buffer

```crystal
termisu.set_cell(x, y, 'A', fg: Color.red, bg: Color.black, attr: Attribute::Bold)
termisu.clear                 # Clear buffer
termisu.render                # Apply changes (diff-based)
termisu.sync                  # Force full redraw
```

### Cursor

```crystal
termisu.set_cursor(x, y)
termisu.hide_cursor
termisu.show_cursor
```

### Events

```crystal
# Blocking
event = termisu.poll_event

# With timeout (ms or Time::Span)
event = termisu.poll_event(100)
event = termisu.poll_event(100.milliseconds)

# Non-blocking
event = termisu.try_poll_event

# Iterator
termisu.each_event do |event|
end
```

### Timer

```crystal
termisu.enable_timer(16.milliseconds)
termisu.enable_system_timer(16.milliseconds)
termisu.disable_timer
termisu.timer_enabled?
termisu.timer_interval = 8.milliseconds
```

### Terminal Modes

```crystal
termisu.suspend { }                        # Shell-out
termisu.with_cooked_mode { }                  # Shell mode
termisu.with_cbreak_mode { }                   # Echo input
termisu.with_password_mode { }                # Hidden input
termisu.with_mode(mode) { }                    # Custom mode
```

### Mouse & Keyboard

```crystal
termisu.enable_mouse
termisu.disable_mouse
termisu.mouse_enabled?

termisu.enable_enhanced_keyboard
termisu.disable_enhanced_keyboard
termisu.enhanced_keyboard?
```

## Architecture Insights

### Layering

```
Application (user code)
    ↓
Termisu API (facade)
    ↓
Components (Buffer, Cell, Color, Event)
    ↓
Terminal Abstraction (TTY, Termios, Terminfo)
    ↓
System (POSIX APIs)
```

### Event Flow

```
Input Source (keyboard/mouse/timer)
    ↓
Event::Loop (fiber + channel)
    ↓
Event Parser (escape sequences)
    ↓
Event Dispatcher (poll_event)
    ↓
Application (case event)
```

### Rendering Pipeline

```
User API (set_cell)
    ↓
Back Buffer (modifications)
    ↓
Render (diff front vs back)
    ↓
Render State (escape sequence optimization)
    ↓
Terminal (TTY write)
```

## Key Conventions

- **Files:** kebab-case (`buffer.cr`)
- **Classes:** PascalCase (`Termisu::Buffer`)
- **Methods:** snake_case (`set_cell`)
- **Predicates:** `?` suffix (`raw_mode?`)
- **Setters:** `=` suffix (`foreground=`)
- **Lifecycle:** `enable_`/`disable_` or `start`/`stop`

## Build Commands

```bash
# Run all tests
bin/hace spec

# Format code
bin/hace format

# Run linter
bin/hace ameba

# Run examples
bin/hace demo
bin/hace showcase
bin/hace animation
```

## Logging

```bash
TERMISU_LOG_LEVEL=debug    # trace, debug, info, warn, error, fatal, none
TERMISU_LOG_FILE=/tmp/termisu.log
TERMISU_LOG_SYNC=true      # sync for real-time debugging
```
