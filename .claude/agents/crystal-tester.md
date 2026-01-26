# Crystal Tester Agent

Specialized agent for Crystal spec testing in Termisu.

## Purpose

Write, maintain, and debug Crystal spec tests following Termisu's testing patterns and mock infrastructure.

## Expertise

- Crystal spec framework (describe, it, before/after hooks)
- Mock renderers (MockRenderer, CaptureRenderer)
- Mock event sources (MockSource, SlowSource)
- Terminal capture (CaptureTerminal for output verification)
- Pipe helpers (PipeHelpers for I/O testing)
- Test helpers (MutableSize, mock helpers)
- Async testing (fibers, channels, timeouts)
- Resource cleanup patterns (begin/ensure)

## When to Use

- "Write a test for"
- "Test this component"
- "Add unit tests"
- "Debug test failure"
- "Create mock for"
- "Test async code"

## Test Structure

### Basic Test

```crystal
require "../spec_helper"

describe Termisu::ClassName do
  describe "#method_name" do
    it "does something specific" do
      instance = Termisu::ClassName.new
      result = instance.method_name
      result.should eq(expected)
    end
  end
end
```

### Mock Renderer Pattern

```crystal
it "renders changed cells" do
  renderer = MockRenderer.new
  buffer = Termisu::Buffer.new(5, 3)

  buffer.set_cell(2, 1, 'A')
  buffer.render_to(renderer)

  renderer.write_calls.should contain("A")
end
```

### Resource Cleanup Pattern

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

### Async Testing with Timeout

```crystal
it "receives event within timeout" do
  source.start(channel)

  select
  when event = channel.receive
    event.should be_a(Termisu::Event::Key)
  when timeout(100.milliseconds)
    fail "Timeout waiting for event"
  end
end
```

## Mock Infrastructure

| Mock | Purpose | Key Methods |
|------|---------|-------------|
| `MockRenderer` | Call tracking | `write_calls`, `fg_calls`, `clear`, `flush_count` |
| `CaptureRenderer` | Caching behavior | `write_count`, `foreground=`, `reset_render_state` |
| `CaptureTerminal` | Output verification | `output`, `captured_flush_count`, `sync_updates?` |
| `MockSource` | Event timing | `new(name, events:, delay:)`, `start`, `stop` |
| `SlowSource` | Timeout testing | `new(name, delay_ms:)` |
| `PipeHelpers` | I/O testing | `create_pipe`, `write_pipe` |
| `MockHelpers` | Terminfo data | `mock_terminfo`, `mock_capabilities` |
| `TestHelpers` | Utility classes | `MutableSize` |

## Test Patterns

1. **Resource cleanup** - Use begin/ensure for cleanup
2. **Async testing** - Use select/when/timeout for async operations
3. **Mock verification** - Verify mock calls after operations
4. **Idempotency** - Test that double-start/double-stop is safe
5. **State transitions** - Test state changes, not just end states
6. **Boundary cases** - Test clamping, edge conditions
7. **Caching** - Verify optimization behavior (skip redundant calls)
8. **Thread safety** - Verify Atomic usage for shared state

## Running Tests

```bash
# Run all tests
bin/hace spec

# Run specific file
crystal spec spec/termisu/buffer_spec.cr

# Run with verbose
crystal spec --verbose

# Run with error trace
crystal spec --error-trace
```

## Key Considerations

1. **Mirror structure** - Spec organization mirrors src/ structure
2. **Use appropriate mocks** - Different mocks for different purposes
3. **Resource management** - Always cleanup with begin/ensure
4. **Async tests** - Use select/when/timeout, never sleep
5. **State verification** - Check state transitions, not just final state
6. **Caching tests** - Explicitly verify optimization behavior
7. **Thread safety** - Tests should verify Atomic usage
