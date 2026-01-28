# Termisu Async Patterns

Asynchronous programming patterns for Termisu TUI applications using Crystal fibers and channels.

## When to Use

- "Background task"
- "Async operation"
- "Fiber communication"
- "Channel usage"
- "Blocking I/O in TUI"
- "Concurrency"

## Fiber Basics

### Spawning a Fiber

```crystal
# Simple fiber
spawn do
  puts "Running in fiber"
end

# Fiber with parameters
spawn do |name|
  puts "Hello, #{name}!"
end
```

### Fiber Lifetime

```crystal
# Keep reference for later control
@fiber = spawn do
  loop do
    # ... work ...
    break if @stopped
  end
end

# Stop fiber
@stopped = true
@fiber.join  # Wait for completion
```

## Channel Communication

### Basic Channel

```crystal
channel = Channel(String).new

# Producer
spawn do
  channel.send("Hello")
  channel.send("World")
end

# Consumer
spawn do
  loop do
    msg = channel.receive
    puts "Got: #{msg}"
  end
end
```

### Non-blocking Receive

```crystal
# Receive with timeout
select
  when msg = channel.receive
    puts "Got: #{msg}"
  when timeout(1.second)
    puts "Timeout"
end
```

### Buffered Channel

```crystal
# Buffer size 10
channel = Channel(Int32).new(10)

# Producer can send up to 10 without blocking
10.times { |i| channel.send(i) }
```

## Async Operations in TUI

### Background Task While TUI Runs

```crystal
# Start async operation
result_channel = Channel(ResultType).new

spawn do
  # Long-running operation
  result = fetch_data_from_api
  result_channel.send(result)
end

# Event loop continues
loop do
  if event = termisu.poll_event(10)
    # Handle events
  end

  # Check for async result (non-blocking)
  if result = result_channel.receive_timeout?
    handle_result(result)
  end

  termisu.render
end
```

### Progress Indicator

```crystal
class ProgressTask
  @progress = Channel(Int32).new
  @done = Channel(Nil).new

  def run
    spawn do
      100.times do |i|
        @progress.send(i)
        sleep 0.01
      end
      @done.send(nil)
    end
  end

  def handle_event(termisu)
    # Check progress
    if progress = @progress.receive_timeout?
      draw_progress(termisu, progress)
    end

    # Check if done
    if @done.receive_timeout?
      return true  # Task complete
    end

    false
  end

  private def draw_progress(termisu, progress)
    bar_width = 40
    filled = (progress * bar_width / 100).to_i

    bar = ("=" * filled) + (" " * (bar_width - filled))
    text = "[#{bar}] #{progress}%"

    text.each_char_with_index do |char, idx|
      termisu.set_cell(idx, 0, char, fg: Color.green)
    end
  end
end

# Usage
task = ProgressTask.new
task.run

loop do
  if event = termisu.poll_event(10)
    break if event.key.escape?
  end

  break if task.handle_event(termisu)
  termisu.render
end
```

### Multiple Async Workers

```crystal
# Worker pool
class WorkerPool(T)
  @jobs = Channel(Proc(T)).new
  @results = Channel(T).new
  @workers = [] of Fiber

  def initialize(size : Int32)
    size.times do
      @workers << spawn_worker
    end
  end

  def submit(&job : -> T)
    @jobs.send(job)
  end

  def result : T?
    @results.receive_timeout?
  end

  private def spawn_worker
    spawn do
      loop do
        job = @jobs.receive
        result = job.call
        @results.send(result)
      end
    end
  end
end

# Usage
pool = WorkerPool(Int32).new(4)  # 4 workers

# Submit jobs
10.times do |i|
  pool.submit { compute_expensive(i) }
end

# Collect results
10.times do
  result = pool.result
  puts "Got: #{result}"
end
```

## Event Source Pattern

### Custom Event Source

```crystal
class CustomSource < Termisu::Event::Source
  @running = Atomic(Bool).new(false)
  @fiber : Fiber?

  def initialize(@name : String = "CustomSource")
  end

  def start(output : Channel(Termisu::Event::Any))
    return if @running.true?

    @running.set_true
    @fiber = spawn do
      while @running.true?
        # Generate events
        output.add(Termisu::Event::Key.new(Termisu::Input::Key::Space))
        sleep 1.second
      end
    end
  end

  def stop
    @running.set_false
    @fiber.try(&.join)
  end

  def running?
    @running.true?
  end

  def name
    @name
  end
end

# Usage
source = CustomSource.new("Ticker")
termisu.add_event_source(source)
```

### Idempotent Start/Stop

```crystal
class SafeSource < Termisu::Event::Source
  def start(output)
    return if @running.true?
    @running.set_true
    # ... start ...
  end

  def stop
    return unless @running.true?
    @running.set_false
    # ... stop ...
  end
end

# Safe in ensure blocks
begin
  source.start(channel)
ensure
  source.stop  # Safe even if start failed
end
```

## Fiber Coordination

### Waiting for Multiple Fibers

```crystal
channels = Array(Int32).new(3).map { Channel(Int32).new }

# Start producers
channels.each_with_index do |ch, i|
  spawn do
    sleep (i + 1) * 0.1.seconds
    ch.send(i * 10)
  end
end

# Wait for all results
results = channels.map do |ch|
  ch.receive
end

puts results  # [0, 10, 20]
```

### Select Pattern

```crystal
# Wait for first of multiple sources
select
  when msg = channel_a.receive
    puts "A said: #{msg}"
  when msg = channel_b.receive
    puts "B said: #{msg}"
  when timeout(1.second)
    puts "Timeout"
end
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

sleep 0.1.seconds
puts counter.count  # 2000
```

### Mutex for Complex State

```crystal
require "mutex"

class SafeList(T)
  @mutex = Mutex.new
  @items = [] of T

  def add(item : T)
    @mutex.synchronize do
      @items << item
    end
  end

  def each
    @mutex.synchronize do
      @items.each { |item| yield item }
    end
  end
end
```

## Fiber Yielding

### Cooperative Multitasking

```crystal
# Long-running task should yield
def process_large_data(data)
  data.each_chunk(1000) do |chunk|
    process_chunk(chunk)
    Fiber.yield  # Let other fibers run
  end
end
```

### Priority-based Yielding

```crystal
# Important fiber runs more often
spawn do
  loop do
    handle_urgent_events
    Fiber.yield  # Still yield, but frequently
  end
end

# Background fiber yields more
spawn do
  loop do
    do_background_work
    sleep 0.1  # Yield longer
  end
end
```

## Resource Cleanup

### Ensure Fiber Cleanup

```crystal
class ManagedResource
  @running = Atomic(Bool).new(false)
  @fiber : Fiber?

  def start
    return if @running.true?

    @running.set_true
    @fiber = spawn do
      while @running.true?
        do_work
      end
      cleanup  # Always run
    end
  end

  def stop
    @running.set_false
    @fiber.try(&.join)
  end

  private def cleanup
    # Cleanup resources
  end
end
```

### Channel Closing

```crystal
channel = Channel(Int32).new

spawn do
  5.times { |i| channel.send(i) }
ensure
  channel.close  # Signal no more data
end

# Consumer can detect closed channel
begin
  loop do
    msg = channel.receive
    puts msg
  end
rescue Channel::ClosedError
  puts "Channel closed"
end
```

## Common Patterns

### Debounce

```crystal
class Debouncer
  @channel = Channel(T).new
  @delay : Time::Span

  def initialize(@delay)
    @debounce_fiber = spawn do_loop
  end

  def push(value : T)
    @channel.send(value)
  end

  private def do_loop
    last_value = nil

    loop do
      value = @channel.receive
      start = Time.instant

      # Collect more values during delay
      while (Time.instant - start) < @delay
        if new_value = @channel.receive_timeout?
          value = new_value
          start = Time.instant  # Reset timer
        end
      end

      process(value)
    end
  end
end
```

### Throttle

```crystal
class Throttler
  @min_interval : Time::Span
  @last_run = Time.instant

  def initialize(@min_interval)
  end

  def run
    now = Time.instant
    elapsed = now - @last_run

    if elapsed >= @min_interval
      @last_run = now
      yield
    end
  end
end

# Usage
throttler = Throttler.new(1.second)

loop do
  throttler.run do
    expensive_operation
  end
end
```

### Batch Processor

```crystal
class BatchProcessor(T)
  @batch_size : Int32
  @timeout : Time::Span
  @input = Channel(T).new
  @output = Channel(Array(T)).new

  def initialize(@batch_size, @timeout)
    spawn do_process
  end

  def push(item : T)
    @input.send(item)
  end

  def flush : Array(T)?
    @output.receive_timeout?
  end

  private def do_process
    batch = [] of T
    deadline = Time.instant

    loop do
      item = @input.receive

      batch << item

      if batch.size >= @batch_size
        @output.send(batch)
        batch = []
        deadline = Time.instant + @timeout
      elsif (Time.instant - deadline) >= @timeout
        @output.send(batch) unless batch.empty?
        batch = []
        deadline = Time.instant + @timeout
      end
    end
  end
end
```

## Quick Reference

| Task | Pattern |
|------|---------|
| Background task | `spawn { }` + Channel for result |
| Non-blocking receive | `select` with `timeout` |
| Custom event source | Extend `Event::Source` |
| Thread-safe state | `Atomic(Bool)` or `Mutex` |
| Resource cleanup | `ensure` block in fiber |
| Fiber cooperation | `Fiber.yield` |
| Multiple workers | Pool of fibers with job channel |
