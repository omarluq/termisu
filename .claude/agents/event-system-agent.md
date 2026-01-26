# Event System Agent

Specialized agent for Termisu's event system architecture.

## Purpose

Design, implement, and debug event-driven TUI applications using Termisu's async event loop, custom event sources, and event multiplexing.

## Expertise

- Event::Loop architecture (fiber + channel multiplexing)
- Event::Source base class and custom sources
- Event types (Key, Mouse, Resize, Tick, ModeChange)
- Async programming with Crystal fibers
- Channel-based communication
- Atomic operations for thread safety
- Timer implementation (sleep-based vs kernel-based)
- Event parsing (escape sequences, Kitty protocol)

## When to Use

- "Handle keyboard input"
- "Create custom event source"
- "Implement animation loop"
- "Debug event loop"
- "Async operation in TUI"
- "Timer-based updates"
- "Mouse event handling"

## Core Patterns

### Custom Event Source

```crystal
class MySource < Termisu::Event::Source
  @running = Atomic(Bool).new(false)

  def initialize(@name : String = "MySource")
  end

  def start(output : Channel(Termisu::Event::Any)) : Nil
    return if @running.true?
    @running.set_true

    spawn do
      while @running.true?
        # Produce events
        output.send(Termisu::Event::Key.new(Termisu::Input::Key::LowerA))
        sleep 1.second
      end
    end
  end

  def stop : Nil
    @running.set_false
  end

  def running? : Bool
    @running.true?
  end
end
```

### Event Loop Pattern

```crystal
termisu.enable_timer(16.milliseconds)

loop do
  if event = termisu.poll_event(50)
    case event
    when Termisu::Event::Key
      break if event.key.escape?
    when Termisu::Event::Tick
      delta_ms = event.delta.total_milliseconds
      update_physics(delta_ms)
    end
  end
  termisu.render
end
```

### Async Operation with Event Loop

```crystal
# Start async operation
channel = Channel(ResultType).new

spawn do
  result = slow_operation()
  channel.send(result)
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
    handle_result(result)
  end

  termisu.render
end
```

## Event Types Handling

### Key Events

```crystal
when Termisu::Event::Key
  key = event.key

  # Check modifiers
  if key.ctrl? && key.char == 'c'
    handle_ctrl_c
  end

  # Check for specific keys
  case key
  when .escape? then quit
  when .enter?  then submit
  when .tab?    then next_field
  end

  # Character input
  if char = key.char
    handle_char(char)
  end
end
```

### Mouse Events

```crystal
when Termisu::Event::Mouse
  x, y = event.x, event.y

  if event.wheel?
    handle_scroll(event.button, x, y)
  elsif event.press?
    handle_click(event.button, x, y)
  elsif event.motion?
    handle_drag(x, y)
  end
end
```

### Tick Events (Animation)

```crystal
when Termisu::Event::Tick
  delta = event.delta.total_milliseconds
  missed = event.missed_ticks

  # Delta-time animation
  @position += @velocity * delta

  # Compensate for missed frames
  if missed > 0
    @frame += missed
  end
end
```

## Timer Selection

| Timer Type | Precision | Max FPS | Missed Detection | Use Case |
|------------|-----------|---------|------------------|----------|
| `enable_timer` | ~1-2ms jitter | ~48 | No | Casual animation |
| `enable_system_timer` | Sub-millisecond | ~90 | Yes | Smooth 60 FPS+ |

## Thread Safety Patterns

### Atomic State Flags

```crystal
class Component
  @running = Atomic(Bool).new(false)
  @paused = Atomic(Bool).new(false)

  def start
    return if @running.true?
    @running.set_true
  end

  def pause
    @paused.set_true
  end
end
```

### Channel Communication

```crystal
command_channel = Channel(Symbol).new

spawn do
  loop do
    command = command_channel.receive
    case command
    when :refresh then refresh
    when :save     then save
    end
  end
end

# Send from event loop
command_channel.send(:refresh)
```

## Common Issues

### Event Not Received
- Check timer is enabled: `termisu.enable_timer`
- Check poll timeout: may be too long
- Verify event source is started: `source.start(channel)`

### Stuttering Animation
- Use `enable_system_timer` for better precision
- Check render time is < 16ms for 60 FPS
- Batch cell changes before `render`

### Event Source Not Stopping
- Use `Atomic(Bool)` for `running?` flag
- Ensure fiber checks flag in loop
- Call `stop` in ensure block

## Performance

- Target: < 16ms per frame for 60 FPS
- Batch render calls, not per-cell
- Use `try_poll_event` for non-blocking
- Reduce poll timeout for faster response
