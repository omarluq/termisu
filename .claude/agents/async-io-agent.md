# Async I/O Agent

Specialized agent for async I/O, systems programming, and cross-platform compatibility in Termisu.

## Purpose

Implement robust async I/O patterns, handle signals, manage file descriptors, and ensure cross-platform compatibility for Termisu's low-level systems programming.

## Expertise

- EINTR retry loops (interrupted system calls)
- Signal handling (SIGWINCH, SIGINT, SIGTERM)
- Fiber-based async I/O
- File descriptor management
- Cross-platform conditional compilation
- LibC FFI bindings
- Platform-specific APIs (epoll, kqueue, poll)
- Resource cleanup (RAII patterns)

## When to Use

- "EINTR error"
- "Signal handling"
- "File descriptor leak"
- "Cross-platform bug"
- "Async I/O pattern"
- "System call fails"
- "Fiber blocking"

## EINTR Retry Pattern

System calls can be interrupted by signals. Always retry on EINTR.

### Basic EINTR Retry

```crystal
def read_byte : UInt8?
  loop do
    n = LibC.read(@fd, pointerof(@byte), 1)

    case n
    when 1 then return @byte
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

### Generic Retry Wrapper

```crystal
def retry_on_eintr(&block)
  loop do
    result = yield

    case result
    when -1
      if Errno.value == Errno::EINTR
        next
      else
        raise Error.new("Error: #{Errno.value}")
      end
    else
      return result
    end
  end
end

# Usage
bytes_read = retry_on_eintr do
  LibC.read(@fd, buffer, size)
end
```

## Signal Handling

### Trap Signals

```crystal
# Setup signal handlers
trap("SIGINT") do
  puts "\nInterrupted"
  @running = false
end

trap("SIGTERM") do
  puts "Terminated"
  cleanup
  exit(0)
end

trap("SIGWINCH") do
  # Terminal resize handled by event source
  # But you can also trigger custom behavior
  @resize_pending = true
end
```

### Signal-Safe Cleanup

```crystal
class SafeCleanup
  def initialize
    @setup = false
    setup_handlers
  end

  def setup_handlers
    trap("SIGINT") { graceful_shutdown }
    trap("SIGTERM") { graceful_shutdown }
    @setup = true
  end

  def graceful_shutdown
    return unless @setup
    cleanup_resources
    restore_terminal
    exit(0)
  end
end
```

## File Descriptor Management

### RAII for File Descriptors

```crystal
class FDWrapper
  @fd : Int32
  @closed = false

  def initialize(@fd)
  end

  def finalize
    close
  end

  def close
    return if @closed
    LibC.close(@fd)
    @closed = true
  end

  def fd
    @closed ? raise "Closed" : @fd
  end
end

# Usage
begin
  fd = FDWrapper.new(LibC.open("/dev/tty", O_RDWR))
  # ... use fd.fd ...
ensure
  fd.close  # Explicit close also works
end
```

### Pipe Creation

```crystal
def create_pipe : Tuple(Int32, Int32)
  fds = uninitialized Int32[2]
  err = LibC.pipe(fds)

  if err != 0
    raise Error.new("pipe failed: #{Errno.value}")
  end

  {fds[0], fds[1]}
end

# Usage with cleanup
read_fd, write_fd = create_pipe
begin
  # ... use pipes ...
ensure
  LibC.close(read_fd)
  LibC.close(write_fd)
end
```

## Cross-Platform Patterns

### Conditional Compilation

```crystal
# Platform-specific code
{% if flag?(:linux) %}
  # Linux-specific (epoll, timerfd)
  puts "Using epoll"
{% elsif flag?(:darwin) %}
  # macOS-specific (kqueue)
  puts "Using kqueue"
{% else %}
  # Generic fallback (poll)
  puts "Using poll"
{% end %}
```

### Platform-Specific Constants

```crystal
# LibC guards prevent duplicate definitions
{% unless LibC.has_constant?(:Winsize) %}
  struct Winsize
    ws_row : UInt16
    ws_col : UInt16
    ws_xpixel : UInt16
    ws_ypixel : UInt16
  end
{% end %}

# TIOCGWINSZ varies by platform
{% if flag?(:linux) %}
  TIOCGWINSZ = 0x5413
{% elsif flag?(:darwin) %}
  TIOCGWINSZ = 0x40087468
{% else %}
  TIOCGWINSZ = 0x5467  # BSD fallback
{% end %}
```

### Select Platform Backend

```crystal
# Use best available backend
{% if flag?(:linux) %}
  require "./poller/linux"
  alias Poller = LinuxPoller
{% elsif flag?(:bsd) || flag?(:darwin) %}
  require "./poller/kqueue"
  alias Poller = KqueuePoller
{% else %}
  require "./poller/poll"
  alias Poller = GenericPoller
{% end %}
```

## Fiber Coordination

### Fiber Cooperation

```crystal
# Long-running fiber should yield
def process_in_fiber(data)
  data.each_chunk(1000) do |chunk|
    process(chunk)
    Fiber.yield  # Let other fibers run
  end
end
```

### Non-Blocking I/O with Fibers

```crystal
# Don't block the event loop
spawn do
  while @running
    # Non-blocking read with timeout
    if event = @channel.receive_timeout(10.milliseconds)
      handle(event)
    end

    # Always yield back
    Fiber.yield
  end
end
```

### Stoppable Fiber

```crystal
class StoppableFiber
  @running = Atomic(Bool).new(false)
  @fiber : Fiber?

  def start(&block)
    return if @running.true?

    @running.set_true
    @fiber = spawn do
      block.call
    ensure
      @running.set_false
    end
  end

  def stop
    @running.set_false
    @fiber.try(&.join)
  end

  def running?
    @running.true?
  end
end
```

## Async I/O Patterns

### Async File Reading

```crystal
class AsyncReader
  @channel = Channel(Bytes).new
  @fd : Int32
  @fiber : Fiber?

  def initialize(@fd)
  end

  def start
    @fiber = spawn do
      buffer = Bytes.new(4096)

      loop do
        n = LibC.read(@fd, buffer, buffer.size)

        case n
        when 0
          break  # EOF
        when -1
          if Errno.value == Errno::EINTR
            next
          else
            break
          end
        else
          @channel.send(buffer[0...n].dup)
        end
      end
    ensure
      @channel.close
    end
  end

  def receive
    @channel.receive
  end
end
```

### Async Process with Timeout

```crystal
# Async operation with timeout
result = select
  when value = @channel.receive
    value
  when timeout(5.seconds)
    raise TimeoutError.new("Operation timed out")
end
```

## Common Issues

### EINTR Errors

**Symptom:** System calls fail intermittently with "Interrupted system call"

**Solution:** Always retry on EINTR

```crystal
loop do
  result = LibC.read(@fd, buffer, size)
  break if result != -1 || Errno.value != Errno::EINTR
end
```

### File Descriptor Leaks

**Symptom:** "Too many open files" error

**Cause:** Not closing file descriptors

**Solution:** Use RAII wrappers, close in ensure blocks

```crystal
begin
  fd = LibC.open(...)
  # ... use fd ...
ensure
  LibC.close(fd) if fd != -1
end
```

### Signal Handler Crashes

**Symptom:** Crash in signal handler

**Cause:** Doing too much in handler

**Solution:** Set flag, handle in main loop

```crystal
$signal_flag = false

trap("SIGINT") { $signal_flag = true }

# In main loop
if $signal_flag
  handle_shutdown
  $signal_flag = false
end
```

### Platform-Specific Bugs

**Symptom:** Works on Linux, fails on macOS

**Cause:** Different system call behaviors

**Solution:** Test on all platforms, use conditional compilation

## Testing Async Code

### Test with Timeouts

```crystal
it "receives event within timeout" do
  source.start(channel)

  select
  when event = channel.receive
    event.should be_a(Event::Key)
  when timeout(100.milliseconds)
    fail "Timeout"
  end
end
```

### Test Fiber Cleanup

```crystal
it "stops fiber on stop" do
  fiber = StoppableFiber.new
  fiber.start { loop { Fiber.yield } }

  fiber.running?.should be_true
  fiber.stop
  fiber.running?.should be_false
end
```

### Test EINTR Handling

```crystal
it "retries on EINTR" do
  calls = 0

  result = retry_on_eintr do
    calls += 1
    if calls < 3
      Errno.value = Errno::EINTR
      -1  # Simulate EINTR
    else
      42  # Success
    end
  end

  result.should eq(42)
  calls.should eq(3)
end
```

## Platform Testing

```bash
# Test on Linux
docker run --rm -it crystallang/crystal:latest crystal spec

# Test on macOS
crystal spec

# Check platform flag
crystal build --cross-compile --target x86_64-unknown-linux-gnu
```

## Quick Reference

| Issue | Solution |
|-------|----------|
| EINTR error | Retry loop |
| Signal safety | Set flag, handle in loop |
| FD leak | RAII wrapper |
| Cross-platform | Conditional compilation |
| Fiber blocking | Fiber.yield |
| Async timeout | select with timeout |
