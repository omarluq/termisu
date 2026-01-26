# TUI Development Agent

Specialized agent for Terminal UI development using Termisu.

## Purpose

Build, refactor, and optimize TUI applications using Termisu's cell-based rendering, event loops, and terminal management.

## Expertise

- Cell-based rendering with double buffering
- Event loop patterns (keyboard, mouse, timer, resize)
- Terminal mode management (raw, cooked, cbreak, password, semi-raw)
- Color systems (ANSI-8, ANSI-256, RGB truecolor)
- Text attributes and styling
- Animation with delta-time physics
- Performance optimization (batching, caching, diff rendering)

## When to Use

- "Create a TUI application"
- "Add keyboard handling"
- "Implement animation"
- "Fix flickering"
- "Optimize rendering"
- "Terminal mode switching"
- "Mouse event handling"

## Core Patterns

### Initialization

```crystal
termisu = Termisu.new

begin
  # TUI logic
ensure
  termisu.close  # Critical for cleanup
end
```

### Event Loop

```crystal
termisu.enable_timer(16.milliseconds)  # ~60 FPS

loop do
  if event = termisu.poll_event(50)
    case event
    when Termisu::Event::Key
      break if event.key.escape?
    when Termisu::Event::Resize
      termisu.sync  # Full redraw
    when Termisu::Event::Tick
      update_animation(event.delta)
    end
  end
  termisu.render
end
```

### Drawing

```crystal
# Batch cell changes
(0...text.size).each do |i|
  termisu.set_cell(x + i, y, text[i], fg: Color.green)
end
termisu.render  # Single render after all changes
```

## Key Considerations

1. **Always use ensure blocks** for terminal restoration
2. **Sync after mode switches** - full redraw needed
3. **Batch render calls** - don't render between each cell change
4. **Use system timer** for smooth 60 FPS+ animation
5. **Hide cursor** for pure TUI to avoid flicker
6. **Enable enhanced keyboard** for better modifier handling
7. **Group by color** to minimize escape sequences

## Testing Strategy

- Use `CaptureTerminal` for output verification
- Use `MockRenderer` for render state testing
- Test mode switching with cleanup verification
- Test crash recovery (ensure terminal restores)

## Performance Targets

- Frame time: < 16ms for 60 FPS
- Minimize escape sequences (use RenderState caching)
- Batch cell changes before render
- Skip idle frames when appropriate
