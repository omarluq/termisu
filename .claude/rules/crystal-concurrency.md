# Crystal Concurrency Patterns

Fiber-based concurrency patterns for Termisu async development.

## When to Use

- "Fiber coordination"
- "Async cleanup"
- "Channel patterns"
- "Fiber blocking"
- "Race condition"
- "Deadlock"

## Fiber Basics

### Spawn a Fiber

```crystal
# Simple fiber
spawn do
  puts "Running in fiber"
end

# Fiber returning value
channel = Channel(Int32).new

spawn do
  result = expensive_computation
  channel.send(result)
end

result = channel.receive
```

### Fiber Lifecycle

```crystal
fiber = spawn do
  loop do
    break if @stopped
    do_work
    Fiber.yield
  end
end

# Check if alive
puts fiber.state  # => :running, :stopped, etc.

# Wait for completion
fiber.join
```

## Thread Safety

### Atomic for State

```crystal
class Counter
  @count = Atomic(Int32).new(0)

  def increment
    @count.add(1)
  end

  def count
    @count.get
  end
end

# Safe across fibers
counter = Counter.new

spawn { 1000.times { counter.increment } }
spawn { 1000.times { counter.increment } }

Fiber.yield until counter.count == 2000
```

### Atomic Boolean

```crystal
class Switch
  @enabled = Atomic(Bool).new(false)

  def enable
    return if @enabled.true?  # Idempotent
    @enabled.set_true
  end

  def disable
    @enabled.set_false
  end

  def enabled?
    @enabled.true?
  end
end
```

### Atomic Compare-and-Swap

```crystal
@state = Atomic(Int32).new(0)

# Compare and set
loop do
  old = @state.get
  new = old + 1
  break if @state.compare_and_set(old, new)
  # CAS failed, retry
end
```

### Mutex for Complex State

```crystal
require "mutex"

class ThreadSafeCache(K, V)
  @mutex = Mutex.new
  @cache = Hash(K, V).new

  def put(key : K, value : V)
    @mutex.synchronize do
      @cache[key] = value
    end
  end

  def get(key : K) : V?
    @mutex.synchronize do
      @cache[key]?
    end
  end
end
```

## Channel Patterns

### Basic Producer-Consumer

```crystal
channel = Channel(Int32).new

# Producer
spawn do
  10.times { |i| channel.send(i) }
  channel.close
end

# Consumer
spawn do
  while msg = channel.receive?
    puts msg
  end
end
```

### Request-Response Pattern

```crystal
class RequestServer
  @requests = Channel(Request).new
  @responses = Hash(Int32, Channel(Response)).new
  @next_id = Atomic(Int32).new(0)

  def start
    spawn do_loop
  end

  def send_request(req : Request) : Response
    id = @next_id.add(1)
    response_ch = Channel(Response).new
    @responses[id] = response_ch

    @requests.send(Request.new(id, req))

    response_ch.receive
  end

  private def do_loop
    loop do
      req = @requests.receive
      response = process(req)
      @responses[req.id].send(response)
    end
  end
end
```

### Buffered Channel

```crystal
# Unbuffered: blocks until receiver ready
ch1 = Channel(Int32).new

# Buffered with capacity
ch2 = Channel(Int32).new(10)

# Producer can send up to 10 without blocking
10.times { |i| ch2.send(i) }
```

### Select Pattern

```crystal
# Wait for first of multiple channels
select
  when msg = channel_a.receive
    puts "A: #{msg}"
  when msg = channel_b.receive
    puts "B: #{msg}"
  when timeout(1.second)
    puts "Timeout"
end
```

## Fiber Coordination

### Barrier Synchronization

```crystal
class Barrier
  def initialize(@count : Int32)
    @waiting = 0
    @mutex = Mutex.new
    @cond = Channel(Nil).new
  end

  def wait
    @mutex.synchronize do
      @waiting += 1
      if @waiting == @count
        @count.times { @cond.send(nil) }
        @waiting = 0
      end
    end

    @cond.receive
  end
end

# Usage
barrier = Barrier.new(3)

3.times do |i|
  spawn do
    do_phase_1
    barrier.wait  # Wait for all fibers
    do_phase_2
  end
end
```

### Worker Pool

```crystal
class WorkerPool(J, R)
  @jobs = Channel(Job(J, R)).new
  @results = Channel(R).new
  @workers = [] of Fiber

  def initialize(size : Int32)
    size.times { spawn_worker }
  end

  def submit(job : J) -> R
    result_ch = Channel(R).new
    @jobs.send(Job.new(job, result_ch))
    result_ch.receive
  end

  private def spawn_worker
    @workers << spawn do
      loop do
        job = @jobs.receive
      result = execute(job.input)
      job.result_channel.send(result)
      end
    end
  end

  struct Job(J, R)
    getter input : J
    getter result_channel : Channel(R)

    def initialize(@input, @result_channel)
    end
  end
end
```

## Resource Cleanup

### Ensure Cleanup

```crystal
class ResourceHolder
  @fiber : Fiber?

  def start
    @fiber = spawn do
      begin
        do_work
      ensure
        cleanup_resources
      end
    end
  end

  def stop
    @fiber.try(&.kill)
  end
end
```

### Stoppable Fiber with Ensure

```crystal
class StoppableTask
  @running = Atomic(Bool).new(false)
  @fiber : Fiber?

  def start
    return if @running.true?

    @running.set_true
    @fiber = spawn do
      begin
        while @running.true?
          do_work
          Fiber.yield
        end
      ensure
        @running.set_false
        cleanup
      end
    end
  end

  def stop
    @running.set_false
    @fiber.try(&.join)
  end
end
```

### Channel Closing

```crystal
channel = Channel(Int32).new

spawn do
  5.times { |i| channel.send(i) }
ensure
  channel.close  # Signal completion
end

# Consumer handles close
begin
  loop do
    msg = channel.receive
    puts msg
  end
rescue Channel::ClosedError
  puts "Channel closed"
end
```

## Fiber Yielding

### Cooperative Multitasking

```crystal
# Long task should yield periodically
def process_large_data(data)
  data.each_chunk(1000) do |chunk|
    process_chunk(chunk)
    Fiber.yield  # Let other fibers run
  end
end
```

### Priority-Based Yielding

```crystal
# Important fiber: yield frequently
spawn do
  loop do
    handle_urgent_events
    Fiber.yield
  end
end

# Background fiber: yield less often
spawn do
  loop do
    do_background_work
    sleep 0.1  # Or yield after timeout
  end
end
```

### Non-Blocking Wait

```crystal
# Instead of blocking sleep
spawn do
  sleep 1.second
  @ready = true
end

# In event loop
loop do
  break if @ready
  # ... other work ...
  Fiber.yield
end
```

## Common Patterns

### Debounce

```crystal
class Debouncer(T)
  @delay : Time::Span
  @input = Channel(T).new
  @output = Channel(T).new
  @fiber : Fiber?

  def initialize(@delay)
    @fiber = spawn do_loop
  end

  def push(value : T)
    @input.send(value)
  end

  private def do_loop
    while true
      value = @input.receive
      deadline = Time.monotonic + @delay

      # Collect more values during delay
      while (Time.monotonic < deadline) && (new_val = @input.receive_timeout?)
        value = new_val
        deadline = Time.monotonic + @delay
      end

      @output.send(value)
    end
  end
end
```

### Throttle

```crystal
class Throttler
  def initialize(@interval : Time::Span)
    @last_run = Time.monotonic - @interval
  end

  def run(&block)
    now = Time.monotonic
    return if (now - @last_run) < @interval

    @last_run = now
    yield
  end
end
```

### Timeout Pattern

```crystal
def with_timeout(timeout : Time::Span)
  result_ch = Channel(T).new

  spawn do
    result = yield
    result_ch.send(result)
  end

  select
  when result = result_ch.receive
    result
  when timeout(timeout)
    raise TimeoutError.new("Operation timed out")
  end
end
```

## Deadlock Prevention

### Consistent Lock Order

```crystal
# Always acquire locks in same order
def safe_transfer(a : Mutex, b : Mutex)
  a.synchronize do
    b.synchronize do
      # Transfer data
    end
  end
end
```

### Timeout on Lock

```crystal
def try_lock(mutex : Mutex, timeout : Time::Span) : Bool
  acquired = false
  spawn do
    mutex.synchronize { acquired = true }
  end

  timeout.times do
    return true if acquired
    Fiber.yield
  end

  false
end
```

### Avoid Holding Locks While Yielding

```crystal
# BAD: Holding lock across yield
@mutex.synchronize do
  do_work
  Fiber.yield  # Deadlock risk!
end

# GOOD: Release lock before yield
result = @mutex.synchronize { get_data }
Fiber.yield
@mutex.synchronize { update(result) }
```

## Race Conditions

### Check-Then-Act Race

```crystal
# BAD: Race condition
if @cache[key]?.nil?
  @cache[key] = compute(key)  # May compute twice
end

# GOOD: Use mutex
@mutex.synchronize do
  if @cache[key]?.nil?
    @cache[key] = compute(key)
  end
end
```

### Double-Checked Locking

```crystal
def get_instance
  return @instance if @instance

  @mutex.synchronize do
    return @instance if @instance
    @instance = create_instance
  end
end
```

## Debugging Concurrency

### Fiber Inspection

```crystal
# List all fibers
Fiber.list.each do |f|
  puts "Fiber: #{f.inspect}, state: #{f.state}"
end

# Check current fiber
puts "Current: #{Fiber.current}"
```

### Channel State

```crystal
# Check if channel closed
begin
  msg = channel.receive
rescue Channel::ClosedError
  puts "Channel closed"
end
```

### Deadlock Detection

```crystal
# Add timeouts to prevent hangs
select
  when msg = channel.receive
    process(msg)
  when timeout(5.seconds)
    raise "Possible deadlock - no activity for 5s"
end
```

## Quick Reference

| Task | Pattern |
|------|---------|
| Thread-safe flag | `Atomic(Bool).new(false)` |
| Thread-safe counter | `Atomic(Int32).new(0)` |
| Complex state | `Mutex.synchronize` |
| Producer-consumer | `Channel(T).new` |
| Multiple wait | `select` with `when` |
| Stop fiber | `Atomic(Bool)` flag |
| Prevent deadlock | Consistent lock order |
| Cooperative yield | `Fiber.yield` |
