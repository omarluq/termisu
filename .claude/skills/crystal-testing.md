# Crystal Testing for Termisu

Crystal spec testing patterns and workflows for Termisu TUI development.

## When to Use

- "How do I run tests?"
- "Write a test for"
- "Test coverage"
- "Mock this component"
- "Test file structure"

## Test Structure

### Organization

```
spec/
├── spec_helper.cr           # Test configuration
├── support/                 # Test utilities (8 files)
│   ├── capture_terminal.cr  # Terminal subclass for output capture
│   ├── capture_renderer.cr  # Renderer with caching behavior
│   ├── mock_renderer.cr     # Comprehensive call-tracking mock
│   ├── mock_source.cr       # Event source mock with delays
│   ├── mock_helpers.cr      # Terminfo mock data generators
│   ├── pipe_helpers.cr      # Unix pipe creation for I/O tests
│   ├── slow_source.cr       # Slow fiber for timeout testing
│   └── test_helpers.cr      # Utility classes (MutableSize)
├── shared/                  # Shared test suites
│   └── poller_shared_tests.cr
└── termisu/                 # Mirrors src/termisu/
    ├── event/               # Event system tests
    ├── input/               # Input parser tests
    ├── terminal/            # Terminal behavior tests
    └── terminfo/            # Terminfo parser tests
```

### Naming Conventions

- **Files**: `{component}_spec.cr` (e.g., `buffer_spec.cr`)
- **Describe blocks**: `Termisu::ClassName` or `"Feature Description"`
- **It blocks**: Verb phrases describing behavior (`"creates a buffer"`)

## Basic Test Structure

```crystal
require "../spec_helper"

describe Termisu::ClassName do
  describe ".new" do
    it "creates with default values" do
      instance = Termisu::ClassName.new
      instance.property.should eq(expected)
    end
  end

  describe "#method_name" do
    it "does something specific" do
      # Arrange
      instance = Termisu::ClassName.new

      # Act
      result = instance.method_name

      # Assert
      result.should eq(expected)
    end
  end
end
```

## Mock Infrastructure

### MockRenderer - Call Tracking

**Purpose:** Comprehensive call-tracking for Buffer/RenderState tests

```crystal
renderer = MockRenderer.new
buffer.render_to(renderer)
renderer.write_calls.should contain("A")
renderer.fg_calls.should eq([Termisu::Color.red])
renderer.clear  # Reset for next test
```

**Tracked Calls:** `write_calls`, `move_calls`, `fg_calls`, `bg_calls`, `flush_count`, attribute counts

### CaptureRenderer - Caching Behavior

**Purpose:** Real caching behavior for optimization tests

```crystal
renderer = CaptureRenderer.new
renderer.foreground = Termisu::Color.red
renderer.foreground = Termisu::Color.red  # Cached
renderer.write_count.should eq(1)  # Only one escape sequence
```

**Features:** Caches fg/bg/attr/cursor, `reset_render_state`, `clear_writes`

### CaptureTerminal - Output Verification

**Purpose:** Terminal subclass that captures all writes

```crystal
terminal = CaptureTerminal.new(sync_updates: true)
terminal.set_cell(0, 0, 'X')
terminal.render
terminal.output.should contain(Termisu::Terminal::BSU)
terminal.captured_flush_count.should eq(1)
```

### MockSource - Event Timing

```crystal
events = [Termisu::Event::Key.new(Termisu::Input::Key::LowerA)]
source = MockSource.new("test", events: events)
channel = Channel(Termisu::Event::Any).new(10)
source.start(channel)
event = channel.receive
source.stop
```

### PipeHelpers - I/O Testing

```crystal
read_fd, write_fd = create_pipe
begin
  reader = Termisu::Reader.new(read_fd)
  parser = Termisu::Input::Parser.new(reader)
  # ... test ...
ensure
  reader.try(&.close)
  LibC.close(read_fd)
  LibC.close(write_fd)
end
```

## Test Patterns

### 1. Resource Cleanup

```crystal
it "cleans up resources" do
  read_fd, write_fd = create_pipe
  begin
    reader = Termisu::Reader.new(read_fd)
    # ... test ...
  ensure
    reader.try(&.close)
    LibC.close(read_fd)
    LibC.close(write_fd)
  end
end
```

### 2. Async Testing with Timeouts

```crystal
it "receives event within timeout" do
  source.start(channel)

  bytes = Bytes['a'.ord.to_u8]
  LibC.write(write_fd, bytes, bytes.size)

  select
  when event = channel.receive
    event.should be_a(Termisu::Event::Key)
  when timeout(100.milliseconds)
    fail "Timeout waiting for event"
  end
end
```

### 3. Mock Verification

```crystal
it "only renders changed cells" do
  renderer = MockRenderer.new
  buffer = Termisu::Buffer.new(5, 3)

  buffer.set_cell(2, 1, 'A')
  buffer.render_to(renderer)
  renderer.clear

  buffer.set_cell(0, 2, 'B')
  buffer.render_to(renderer)

  renderer.write_calls.should contain("B")
  renderer.write_calls.should_not contain("A")
end
```

### 4. Idempotency Testing

```crystal
it "prevents double-start" do
  loop = Termisu::Event::Loop.new
  loop.start
  loop.running?.should be_true

  loop.start  # No-op
  loop.running?.should be_true

  loop.stop
end
```

### 5. State Transition Testing

```crystal
it "transitions from not running to running" do
  source = MockSource.new
  source.running?.should be_false

  source.start(channel)
  source.running?.should be_true

  source.stop
  source.running?.should be_false
end
```

### 6. Boundary/Edge Cases

```crystal
it "clamps cursor to buffer bounds" do
  buffer = Termisu::Buffer.new(10, 8)
  buffer.set_cursor(15, 4)  # x > width

  buffer.cursor.x.should eq(9)  # Clamped to width-1
  buffer.cursor.y.should eq(4)
end
```

### 7. Caching/Optimization Testing

```crystal
it "skips redundant color changes" do
  renderer = CaptureRenderer.new

  renderer.foreground = Termisu::Color.red
  renderer.foreground = Termisu::Color.red  # Cached

  renderer.write_count.should eq(1)  # Only one escape sequence
end
```

### 8. Thread Safety Testing

```crystal
it "uses Atomic for thread-safe state" do
  source = Termisu::Event::Source::Input.new(reader, parser)

  spawn do
    source.start(channel)
    started.send(nil)
    stopped.receive
    source.stop
  end

  started.receive
  source.running?.should be_true
  stopped.send(nil)
end
```

## Running Tests

```bash
# Run all tests
bin/hace spec

# Run specific test file
crystal spec spec/termisu/buffer_spec.cr

# Run with verbose output
crystal spec --verbose

# Run with error trace
crystal spec --error-trace

# Run specific test
crystal spec spec/termisu/buffer_spec.cr:27
```

## Crystal Spec Conventions

### Expectations

```crystal
# Equality
should eq(value)
should_not eq(value)

# Boolean
be_true
be_false

# Type checking
be_a(Type)

# Collections
contain(item)
be_empty
have_size(n)

# Nil checks
be_nil
should_not be_nil

# Comparison
be < n
be > n
be_within(delta).of(expected)
```

### Lifecycle Hooks

```crystal
before_all do
  # Runs once before all tests in describe
end

before_each do
  # Runs before each test
end

after_each do
  # Runs after each test
end

after_all do
  # Runs once after all tests
end
```

### Pending Tests

```crystal
pending "add this feature" do
  # Test will be skipped
end
```

## Key Patterns

1. **Mirror Structure** - Spec organization mirrors source exactly
2. **Mock Layer Matters** - Different mocks for different purposes
3. **Resource Management** - Extensive use of `begin/ensure` for cleanup
4. **Async Testing** - Heavy use of `select/when/timeout`
5. **Thread Safety** - Tests explicitly verify `Atomic` usage
6. **State Testing** - Verify state transitions, not just end states
7. **Caching Verification** - Tests verify optimization behavior
