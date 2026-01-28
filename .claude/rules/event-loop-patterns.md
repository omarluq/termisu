# Event Loop Patterns

Async event handling patterns for Termisu TUI development using Crystal fibers and channels.

## When to Use

- "Handle keyboard input"
- "Animation loop"
- "Multiple event sources"
- "Async operations in TUI"
- "Timer-based updates"

## Core Event Loop Pattern

### Basic Manual Polling

```crystal
termisu = Termisu.new

begin
  loop do
    # Poll with timeout (ms)
    if event = termisu.poll_event(50)
      case event
      when Termisu::Event::Key
        break if event.key.escape?
        handle_key(event.key)
      when Termisu::Event::Mouse
        handle_mouse(event)
      when Termisu::Event::Resize
        termisu.sync  # Full redraw on resize
      when Termisu::Event::Tick
        handle_tick(event)
      end
    end

    # Render every loop iteration
    termisu.render
  end
ensure
  termisu.close
end
```

### Iterator-Based Event Loop

```crystal
# Blocks until event available, no timeout needed
termisu.each_event do |event|
  case event
  when Termisu::Event::Key
    break if event.key.escape?
  when Termisu::Event::Tick
    update_animation
  end

  termisu.render
end

termisu.close
```

**Use iterator when:** You don't need idle rendering between events.

## Event Types

### Key Events

```crystal
when Termisu::Event::Key
  key = event.key

  # Basic keys
  break if key.escape?
  submit if key.enter?

  # Character keys
  if key.char?
    char = key.char  # Char?
    handle_char(char) if char
  end

  # Modifiers
  if key.ctrl? && key.char == 'c'
    handle_ctrl_c
  end

  # Special keys
  case key
  when .tab?       then handle_tab
  when .backspace? then handle_backspace
  when .up?        then move_cursor(0, -1)
  when .down?      then move_cursor(0, 1)
  when .left?      then move_cursor(-1, 0)
  when .right?     then move_cursor(1, 0)
  end
end
```

### Mouse Events

```crystal
when Termisu::Event::Mouse
  x = event.x
  y = event.y

  if event.wheel?
    # Scroll wheel
    if event.button == Mouse::Wheel::Up
      scroll_up
    else
      scroll_down
    end
  elsif event.press?
    # Button press
    case event.button
    when Mouse::Button::Left   then handle_left_click(x, y)
    when Mouse::Button::Middle then handle_middle_click(x, y)
    when Mouse::Button::Right  then handle_right_click(x, y)
    end
  elsif event.release?
    # Button release
    handle_release(x, y)
  elsif event.motion?
    # Drag/motion
    handle_drag(x, y)
  end
end
```

### Resize Events

```crystal
when Termisu::Event::Resize
  new_width = event.width
  new_height = event.height

  # Always sync on resize (full redraw)
  termisu.sync

  # Or handle more carefully:
  if new_width < @min_width || new_height < @min_height
    show_error("Terminal too small")
  else
    resize_buffers(new_width, new_height)
  end
end
```

### Tick Events (Animation)

```crystal
# Enable timer first
termisu.enable_timer(16.milliseconds)  # ~60 FPS

when Termisu::Event::Tick
  # Timing information
  delta = event.delta                # Time::Span since last tick
  delta_ms = delta.total_milliseconds
  missed = event.missed_ticks        # Integer count of missed frames

  # Update with delta time
  @position += @velocity * delta_ms
  @frame += 1

  # Compensate for missed frames
  if missed > 0
    puts "Missed #{missed} frames!"
  end

  # Update physics/rendering
  render_frame(delta_ms)
end
```

## Timer Comparison

| Feature | Timer (sleep) | SystemTimer (kernel) |
|---------|---------------|---------------------|
| Mechanism | `sleep` in fiber | timerfd/epoll (Linux), kqueue (macOS) |
| Precision | ~1-2ms jitter | Sub-millisecond |
| Max FPS | ~48 FPS reliable | ~90 FPS reliable |
| Missed detection | No | Yes (`event.missed_ticks`) |
| Use case | Casual animation | Smooth 60 FPS+ |

```crystal
# Sleep-based timer (portable)
termisu.enable_timer(16.milliseconds)

# Kernel-based timer (more precise)
termisu.enable_system_timer(16.milliseconds)

# Runtime switching
termisu.disable_timer
termisu.enable_system_timer(8.milliseconds)  # Switch to 120 FPS

# Check interval
termisu.timer_interval = 20.milliseconds  # Change on the fly
```

## Async Patterns

### Custom Event Source

```crystal
class MySource < Termisu::Event::Source
  @running = Atomic(Bool).new(false)
  @fiber : Fiber?

  def initialize(@name : String = "MySource")
  end

  def start(output : Channel(Termisu::Event::Any)) : Nil
    return if @running.true?

    @running.set_true(true)
    @fiber = spawn do
      while @running.true?
        # Produce events
        output.send(Termisu::Event::Key.new(Termisu::Input::Key::LowerA))
        sleep 1.second
      end
    end
  end

  def stop : Nil
    @running.set_false
    @fiber.try(&.join)
  end

  def running? : Bool
    @running.true?
  end

  def name : String
    @name
  end
end

# Register with Termisu
my_source = MySource.new("Ticker")
termisu.add_event_source(my_source)
```

### Blocking Operations in Event Loop

**Pattern:** Use fibers for blocking I/O

```crystal
# Start async operation
channel = Channel(String).new

spawn do
  # Blocking operation in fiber
  result = HTTP::Client.get("https://api.example.com")
  channel.send(result.body)
end

# Event loop continues
loop do
  if event = termisu.poll_event(10)
    case event
    when Termisu::Event::Key
      break if event.key.escape?
    end
  end

  # Check for async result (non-blocking)
  if result = channel.receive_timeout?
    handle_api_result(result)
  end

  termisu.render
end
```

### Multiple Event Channels

```crystal
# Merge multiple channels
main_channel = Channel(Termisu::Event::Any).new

# Start multiple sources
input_source = Termisu::Event::Source::Input.new(reader, parser)
timer_source = Termisu::Event::Source::Timer.new(16.milliseconds)

input_source.start(main_channel)
timer_source.start(main_channel)

# Process unified stream
loop do
  event = main_channel.receive
  # Handle event
end
```

## Thread Safety Patterns

### Atomic for State Flags

```crystal
class MyComponent
  @running = Atomic(Bool).new(false)
  @paused = Atomic(Bool).new(false)

  def start
    return if @running.true?  # Idempotent
    @running.set_true
  end

  def pause
    @paused.set_true
  end

  def resume
    @paused.set_false
  end

  def running?
    @running.true?
  end

  def paused?
    @paused.true?
  end
end
```

### Channel for Communication

```crystal
# Producer-consumer pattern
command_channel = Channel(Symbol).new

# Command processor
spawn do
  loop do
    command = command_channel.receive
    case command
    when :refresh then refresh_data
    when :save     then save_data
    when :quit     then break
    end
  end
end

# Send from event loop
when Termisu::Event::Key
  case key
  when .char?('r') then command_channel.send(:refresh)
  when .char?('s') then command_channel.send(:save)
  end
end
```

## Animation Patterns

### Frame-Based Animation

```crystal
termisu.enable_timer(16.milliseconds)  # ~60 FPS

@frame = 0
@objects = [] of GameObject

loop do
  if event = termisu.poll_event
    case event
    when Termisu::Event::Tick
      @frame += 1

      # Update all objects
      @objects.each(&.update)

      # Clear and render
      termisu.clear
      @objects.each do |obj|
        obj.render(termisu)
      end
    when Termisu::Event::Key
      break if event.key.escape?
    end
  end

  termisu.render
end
```

### Smooth Animation with Delta Time

```crystal
@position = 0.0
@velocity = 100.0  # pixels per second

when Termisu::Event::Tick
  dt = event.delta.total_seconds  # Fractional seconds

  # Update position using delta time for smooth animation
  @position += @velocity * dt

  # Clamp to screen bounds
  @position = @position.clamp(0.0, screen_width.to_f)

  render_position(@position)
end
```

### Paused Animation

```crystal
@paused = false

when Termisu::Event::Tick
  next if @paused  # Skip update but continue loop
  update_animation
end

when Termisu::Event::Key
  case key
  when .char?(' ') then @paused = !@paused  # Toggle pause
  end
end
```

## Enhanced Keyboard

**Enable for better key distinction:**

```crystal
termisu.enable_enhanced_keyboard

# Now distinguish Tab from Ctrl+I
case event.key
when .tab?
  # Definitely Tab, not Ctrl+I
when .ctrl? && .char?('\t')  # This won't happen with enhanced
  # Ctrl+I (rare)
end

# Better modifier handling
parts = [] of String
parts << "Ctrl+" if event.ctrl?
parts << "Alt+" if event.alt?
parts << "Shift+" if event.shift?
parts << key.to_s

description = parts.join
# Examples: "Ctrl+Shift+A", "Alt+Enter"
```

## Performance Patterns

### Batch Rendering

```crystal
# Don't render on every cell change
@dirty = false

100.times do |i|
  termisu.set_cell(i, 0, 'X', fg: Color.red)
  @dirty = true
end

# Render once after all changes
termisu.render if @dirty
```

### Adaptive Frame Rate

```crystal
@target_fps = 60
@actual_fps = 0.0
@last_frame = Time.instant

when Termisu::Event::Tick
  now = Time.instant
  delta = now - @last_frame
  @last_frame = now

  # Calculate actual FPS
  @actual_fps = 1.0 / delta.total_seconds if delta.total_seconds > 0

  # Adjust target based on performance
  if @actual_fps < @target_fps * 0.9
    @target_fps = (@target_fps * 0.9).to_i.clamp(15, 60)
  end

  update_and_render
end
```

### Skip Frames When Idle

```crystal
@idle_seconds = 0
@last_activity = Time.instant

when Termisu::Event::Key, Termisu::Event::Mouse
  @last_activity = Time.instant
  @idle_seconds = 0

when Termisu::Event::Tick
  @idle_seconds = (Time.instant - @last_activity).total_seconds

  if @idle_seconds > 5
    # Reduce FPS when idle
    next if (@frame % 4) != 0  # 15 FPS instead of 60
  end

  render
end
```

## Debugging Event Loops

### Event Logging

```crystal
@event_count = 0

loop do
  if event = termisu.poll_event(50)
    @event_count += 1

    # Log events
    puts "Event ##{@event_count}: #{event.class}"

    case event
    when Termisu::Event::Key
      puts "  Key: #{event.key}, Ctrl=#{event.ctrl?}, Alt=#{event.alt?}"
    when Termisu::Event::Mouse
      puts "  Mouse: x=#{event.x}, y=#{event.y}, button=#{event.button}"
    when Termisu::Event::Tick
      puts "  Tick: delta=#{event.delta.total_milliseconds}ms"
    end
  end
end
```

### Profiling

```crystal
require "benchmark"

loop do
  if event = termisu.poll_event(50)
    case event
    when Termisu::Event::Tick
      # Profile update function
      time = Benchmark.measure do
        update_and_render
      end

      puts "Frame time: #{time.total_milliseconds}ms" if time.total_milliseconds > 16
    end
  end
end
```

## Quick Reference

| Task | Code |
|------|------|
| Enable timer | `termisu.enable_timer(16.milliseconds)` |
| Enable system timer | `termisu.enable_system_timer(16.milliseconds)` |
| Disable timer | `termisu.disable_timer` |
| Check timer | `termisu.timer_enabled?` |
| Change interval | `termisu.timer_interval = 20.milliseconds` |
| Enable mouse | `termisu.enable_mouse` |
| Enable enhanced keyboard | `termisu.enable_enhanced_keyboard` |
| Poll with timeout | `termisu.poll_event(50)` |
| Non-blocking poll | `termisu.try_poll_event` |
| Iterator loop | `termisu.each_event { |event| ... }` |
| Full redraw | `termisu.sync` |
| Add event source | `termisu.add_event_source(source)` |

## Best Practices

1. **Always use ensure** for cleanup (disable timer, close terminal)
2. **Use timeout in poll** to allow idle rendering
3. **Sync on resize** - terminal size changed, full redraw needed
4. **Batch cell changes** - don't render between each set_cell
5. **Use fibers** for blocking operations to keep event loop responsive
6. **Atomic for flags** - thread-safe boolean state
7. **Channel for communication** - between fibers and event loop
8. **Prefer system timer** for smooth 60 FPS+ animation
9. **Enable enhanced keyboard** for better modifier handling
10. **Profile frame time** - keep under 16ms for 60 FPS
