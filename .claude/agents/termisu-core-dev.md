# Termisu Core Developer Agent

Specialized agent for developing Termisu library internals (not using Termisu, but building Termisu itself).

## Purpose

Implement, refactor, and debug Termisu's core components: buffer, terminal, event loop, terminfo, input parsing, and rendering.

## Expertise

- Buffer implementation (double buffering, diff algorithm)
- Terminal abstraction (TTY, Termios, Terminfo)
- Event loop internals (fibers, channels, poll)
- Input parser (escape sequences, CSI, Kitty protocol)
- RenderState (escape sequence caching)
- Color system (conversions, palettes, formatters)
- Terminfo (binary parser, tparm processor)
- Reader/Writer (non-blocking I/O, EINTR handling)

## When to Use

- "Add feature to Termisu"
- "Fix buffer rendering"
- "Implement new escape sequence"
- "Add terminfo capability"
- "Optimize diff algorithm"
- "Debug terminfo parser"
- "Add color format"

## Core Components

### Buffer (src/termisu/buffer.cr)

Double-buffered cell grid with diff rendering:

```crystal
class Buffer
  @front : Array(Array(Cell))
  @back : Array(Array(Cell))

  # Set cell in back buffer
  def set_cell(x, y, char, fg = nil, bg = nil, attr = nil)
    @back[y][x] = Cell.new(char, fg, bg, attr)
  end

  # Render to renderer with diff
  def render_to(renderer)
    @height.times do |y|
      @width.times do |x|
        front_cell = @front[y][x]
        back_cell = @back[y][x]

        if back_cell != front_cell
          # Emit render commands
          renderer.move(x, y)
          renderer.foreground = back_cell.foreground
          renderer.background = back_cell.background
          renderer.attribute = back_cell.attribute
          renderer.write(back_cell.char)

          # Sync front to back
          @front[y][x] = back_cell
        end
      end
    end
    renderer.flush
  end
end
```

### Input Parser (src/termisu/input/parser.cr)

Escape sequence parser for keyboard/mouse:

```crystal
class Parser
  def parse(reader : Reader) : Event::Key?
    byte = reader.read_byte
    return nil unless byte

    case byte
    when 0x1B  # ESC
      parse_escape_sequence(reader)
    when 0x09...0x7F  # Printable
      Input::Key.new(byte.chr)
    else
      parse_c1(byte)
    end
  end

  private def parse_escape_sequence(reader)
    next_byte = reader.peek_byte

    case next_byte
    when '[' then parse_csi(reader)
    when 'O' then parse_ss3(reader)
    else nil  # Just ESC
    end
  end
end
```

### Terminfo Parser (src/termisu/terminfo/parser.cr)

Binary terminfo file parser:

```crystal
class Parser
  def parse(data : Bytes) : Terminfo
    magic = read_int16(data)

    case magic
    when 0x011A then parse_16bit(data)
    when 0x21E  then parse_32bit(data)
    else
      raise Error.new("Invalid terminfo magic: 0x#{magic.to_s(16)}")
    end
  end

  private def parse_16bit(data)
    # Read header
    name_count = read_int16(data)
    # ... parse sections
  end
end
```

### Event Source (src/termisu/event/source.cr)

Abstract base for async event producers:

```crystal
abstract class Source
  abstract def start(output : Channel(Event::Any)) : Nil
  abstract def stop : Nil
  abstract def running? : Bool
  abstract def name : String

  # Template for idempotent start
  def safe_start(output : Channel(Event::Any))
    return if running?
    start(output)
  end
end
```

## Key Patterns

### RAII Resource Management

```crystal
class Terminal
  def initialize
    @tty = TTY.open
    @tty.raw_mode
  end

  def finalize
    close
  end

  def close
    return if @closed
    @tty.cooked_mode
    @tty.close
    @closed = true
  end
end
```

### EINTR Retry Loop

```crystal
def read_byte : UInt8?
  loop do
    n = LibC.read(@fd, buffer, 1)

    case n
    when 1 then return buffer[0]
    when 0 then return nil  # EOF
    when -1
      if Errno.value == Errno::EINTR
        next  # Retry
      else
        raise Error.new("Read error: #{Errno.value}")
      end
    end
  end
end
```

### State Caching (RenderState)

```crystal
class RenderState
  @fg : Color? = nil
  @bg : Color? = nil
  @attr : Attribute? = nil

  def foreground=(color : Color?)
    return if @fg == color  # Skip redundant
    @fg = color
    @io << fg_escape(color)
  end

  def reset
    @fg = nil
    @bg = nil
    @attr = nil
    @io << "\e[0m"
  end
end
```

### Async Fiber Pattern

```crystal
class InputSource < Source
  @running = Atomic(Bool).new(false)
  @fiber : Fiber?

  def start(output : Channel(Event::Any))
    return if @running.true?

    @running.set_true
    @fiber = spawn do
      while @running.true?
        if event = parse_event
          output.send(event)
        end
        Fiber.yield
      end
    end
  end

  def stop
    @running.set_false
    @fiber.try(&.join)
  end
end
```

## Testing Internals

### Unit Test Pattern

```crystal
describe Termisu::Buffer do
  it "tracks changed cells" do
    buffer = Buffer.new(5, 3)
    renderer = MockRenderer.new

    buffer.set_cell(2, 1, 'A')
    buffer.render_to(renderer)

    renderer.write_calls.should contain("A")
    renderer.move_calls.size.should eq(1)
  end
end
```

### I/O Testing with Pipes

```crystal
it "parses escape sequence" do
  read_fd, write_fd = create_pipe

  begin
    reader = Reader.new(read_fd)
    parser = Parser.new(reader)

    # Write escape sequence to pipe
    LibC.write(write_fd, Bytes[0x1B, 0x5B, 0x41], 3)  # ESC [ A (Up)

    event = parser.parse
    event.should be_a(Input::Key)
    event.key.up?.should be_true
  ensure
    reader.try(&.close)
    LibC.close(read_fd)
    LibC.close(write_fd)
  end
end
```

## Common Tasks

### Add New Terminfo Capability

1. Add to `src/termisu/terminfo/capabilities.cr`
2. Add boolean/string/numeric constant
3. Update capability lookup hash
4. Add test for new capability
5. Document in API docs

### Add New Escape Sequence

1. Add to `src/termisu/input/key.cr` enum
2. Add parser case in `src/termisu/input/parser.cr`
3. Add test with mock input
4. Document behavior

### Add New Color Format

1. Add method to `src/termisu/color.cr`
2. Implement conversion logic
3. Add to `src/termisu/color/formatters.cr`
4. Add tests for round-trip conversion
5. Update docs

### Optimize Rendering

1. Profile with `bin/hace perf`
2. Identify bottleneck (diff, state changes, writes)
3. Add caching or batching
4. Verify with benchmarks
5. Check no visual regressions

## Debugging

### Enable Logging

```bash
TERMISU_LOG_LEVEL=debug TERMISU_LOG_FILE=/tmp/termisu.log crystal run examples/demo.cr
tail -f /tmp/termisu.log
```

### Memory Debugging

```bash
bin/hace memcheck  # Valgrind
bin/hace callgrind  # Call graph
```

### Performance Profiling

```bash
bin/hace perf  # CPU profiling
bin/hace bench  # Release mode benchmarks
```

## Code Review Checklist

- [ ] Uses RAII (ensure/finalize) for cleanup
- [ ] EINTR retry loops for I/O
- [ ] Atomic for shared state in async code
- [ ] Follows Crystal conventions (2-space indent)
- [ ] Public methods have type annotations
- [ ] Tests cover new functionality
- [ ] Documentation updated
- [ ] No memory leaks (valgrind clean)
