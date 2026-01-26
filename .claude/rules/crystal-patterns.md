# Crystal Programming Patterns

Advanced Crystal idioms and patterns for Termisu development.

## When to Use

- "Crystal pattern for..."
- "Idiomatic Crystal"
- "Struct vs class"
- "Module extension"
- "Type union patterns"

## Platform-Specific Compilation

### Conditional Compilation

```crystal
# Platform-specific code
{% if flag?(:linux) %}
  puts "Linux-specific: using epoll"
  require "./poller/linux"
{% elsif flag?(:darwin) %}
  puts "macOS-specific: using kqueue"
  require "./poller/kqueue"
{% elsif flag?(:bsd) %}
  puts "BSD-specific: using kqueue"
  require "./poller/kqueue"
{% else %}
  puts "Generic: using poll"
  require "./poller/poll"
{% end %}
```

### Feature Flags

```crystal
# Check if feature flag is set
{% if flag?(:debug) %}
  puts "Debug mode enabled"
  Log.setup(:debug)
{% end %}

# Compile with: crystal build --debug -Ddebug
```

### Check Constants at Compile Time

```crystal
# LibC constant checks
{% unless LibC.has_constant?(:SomeConstant) %}
  # Define fallback
  SomeConstant = 0x1000
{% end %}

# Check sizeof
{% if LibC::Winsoff.size != 16 %}
  {% raise "Winsize struct size mismatch" %}
{% end %}
```

## Module Extension Pattern

### `extend self` for Namespaces

```crystal
module Helpers
  extend self

  def format_value(value : Int32) : String
    value.to_s
  end
end

# Usage (no `Helpers.` prefix needed if included)
Helpers.format_value(42)  # or just format_value(42) if included
```

### Mixin Modules

```crystal
module Loggable
  def log_info(msg)
    puts "[INFO] #{msg}"
  end
end

class MyClass
  include Loggable

  def do_work
    log_info("Working")
  end
end
```

## Struct vs Class

### Use Struct for Value Types

```crystal
# GOOD: Small, immutable data
struct Cell
  getter char : Char
  getter fg : Color?
  getter bg : Color?

  def initialize(@char, @fg = nil, @bg = nil)
  end

  # Value semantics - copied on assignment
  def copy_with(char = @char, fg = @fg, bg = @bg)
    Cell.new(char, fg, bg)
  end
end
```

### Use Class for Resource Management

```crystal
# GOOD: Has cleanup
class Terminal
  def initialize
    @tty = TTY.open
  end

  def finalize
    close
  end

  def close
    @tty.close
  end
end
```

## Union Types

### Define Union Types

```crystal
# Event can be any of these
alias Event::Any = Key | Mouse | Resize | Tick | ModeChange

# Method using union
def handle_event(event : Event::Any)
  case event
  when Key then handle_key(event)
  when Mouse then handle_mouse(event)
  end
end
```

### Nullable Types

```crystal
# Union with nil
def find_cell(x, y) : Cell?
  return nil if x < 0 || y < 0
  @buffer[y][x]?
end

# Safe navigation
cell = find_cell(x, y)
char = cell.try(&.char) || ' '
```

## Enum Patterns

### Enum Values

```crystal
enum Color
  Black
  Red
  Green

  # Method on enum
  def sgr_code : Int32
    case self
    in Black then 40
    in Red then 41
    in Green then 42
    end
  end
end
```

### Enum from Int

```crystal
enum Key
  Escape = 27
  Enter = 13

  def self.from_value?(value : Int32) : Key?
    each do |key|
      return key if key.value == value
    end
    nil
  end
end
```

## Proc Typing

### Proc Signatures

```crystal
# Define proc type
alias Callback = Proc(Int32, Int32, String)

# Method accepting proc
def register_callback(&block : Int32, Int32 -> String)
  @callbacks << block
end

# Calling proc
result = @callbacks.first.call(10, 20)
```

### Capturing Procs

```crystal
# Proc captures variables
x = 42
capture = -> { x * 2 }

# Can still be called later
capture.call  # 84
```

## Generic Types

### Generic Class

```crystal
class Channel(T)
  def send(value : T)
    @buffer << value
  end

  def receive : T
    @buffer.shift
  end
end

# Usage
channel = Channel(Int32).new
channel.send(42)
value = channel.receive  # Int32
```

### Generic Constraints

```crystal
def process(item : Number) : Number
  item * 2
end

# Works with Int32, Float64, etc.
process(42)      # OK
process(3.14)    # OK
process("42")    # Error
```

## Reflection

### Type Inspection

```crystal
# Get type name
value = 42
typeof(value)  # => Int32

# Check type at runtime
if value.is_a?(Number)
  puts "It's a number"
end

# Class name
puts value.class.name  # => "Int32"
```

### Methods Reflection

```crystal
# List methods
String.methods.each do |method|
  puts method.name
end

# Check if responds to
"hello".responds_to?(:upcase)  # => true
```

## Exception Handling

### Custom Exceptions

```crystal
class TermisuError < Exception
end

class ParseError < TermisuError
  getter line : Int32

  def initialize(message, @line)
    super("#{message} at line #{@line}")
  end
end
```

### Rescue with Type

```crystal
begin
  risky_operation
rescue ex : ParseError
  puts "Parse error: #{ex.message}"
rescue ex : TermisuError
  puts "Termisu error: #{ex.message}"
rescue ex : Exception
  puts "Unexpected: #{ex.message}"
end
```

## Macro Patterns

### Code Generation

```crystal
macro def_property(name, type)
  def {{name}} : {{type}}
    @{{name}}
  end

  def {{name}}=(value : {{type}})
    @{{name}} = value
  end
end

# Usage
def_property size, Int32

# Expands to:
# def size : Int32
#   @size
# end
# def size=(value : Int32)
#   @size = value
# end
```

### Conditional Methods

```crystal
macro debug_log(msg)
  {% if flag?(:debug) %}
    puts "[DEBUG] {{msg}}"
  {% end %}
end

debug_log("This is a debug message")
```

## Iterator Protocol

### Implement Iterator

```crystal
struct RangeIterator(T)
  include Iterator(T)

  def initialize(@start : T, @stop : T, @step : T)
  end

  def next
    if @start >= @stop
      Iterator::Stop.new
    else
      value = @start
      @start += @step
      value
    end
  end
end
```

## Operator Overloading

### Comparison Operators

```crystal
struct Point
  def <=>(other : Point) : Int32
    @x <=> other.x
  end

  def ==(other : Point) : Bool
    @x == other.x && @y == other.y
  end

  # Include Comparable for <, <=, >, >=
  include Comparable
end
```

### Math Operators

```crystal
struct Point
  def +(other : Point) : Point
    Point.new(@x + other.x, @y + other.y)
  end

  def -(other : Point) : Point
    Point.new(@x - other.x, @y - other.y)
  end

  def *(scalar : Int32) : Point
    Point.new(@x * scalar, @y * scalar)
  end
end
```

## Shortcut Methods

### `tap` for Chaining

```crystal
# Modify and return
result = Hash(String, Int32).new.tap do |h|
  h["one"] = 1
  h["two"] = 2
end
```

### `try` for Nil Handling

```crystal
# Safe call
maybe_string = nil
maybe_string.try(&.upcase)  # => nil
```

### `not_nil!` for Asserting

```crystal
# Crash if nil
value = nullable.not_nil!
```

## Quick Reference

| Pattern | When to Use |
|---------|-------------|
| `struct` | Small, immutable data |
| `class` | Resource management |
| `extend self` | Namespace functions |
| `alias X = A \| B` | Union types |
| `try(&.method)` | Safe nil navigation |
| `flag?(:linux)` | Platform code |
| `include Comparable` | Comparison operators |
| `macro` | Code generation |
