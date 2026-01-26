# Crystal Code Conventions

Code style and naming conventions for Crystal development in Termisu.

## When to Use

- "How should I name this?"
- "What's the Crystal convention for X?"
- "Is this following Crystal style?"
- "Formatting code"

## Naming Conventions

### Files
- **Format:** `kebab-case.cr`
- **Examples:** `buffer.cr`, `color_palette.cr`, `event_loop.cr`
- **Directory:** `src/termisu/event/` (mirrors namespace structure)

### Classes/Modules/Structs
- **Format:** `PascalCase`
- **Namespace:** Always under `Termisu::` namespace
- **Examples:**
  ```crystal
  class Termisu::Buffer
  struct Termisu::Cell
  module Termisu::Event
  enum Termisu::Color
  ```

### Methods
- **Format:** `snake_case`
- **Examples:** `set_cell`, `poll_event`, `foreground=`

### Predicates
- **Suffix:** `?`
- **Return:** `Bool`
- **Examples:**
  ```crystal
  def raw_mode? : Bool
  def timer_enabled? : Bool
  def alternate_screen? : Bool
  ```

### Setters
- **Suffix:** `=`
- **Examples:**
  ```crystal
  def foreground=(color : Color?) : Nil
  def timer_interval=(span : Time::Span) : Nil
  ```

### Bang Methods
- **Suffix:** `!`
- **Use:** When method raises on error or has dangerous side effects
- **Examples:** `flush!`, `close!`

### Constants
- **Format:** `PascalCase` or `SCREAMING_SNAKE_CASE`
- **Prefer:** `PascalCase` for most cases
- **Examples:**
  ```crystal
  DEFAULT_SIZE = 80
  MAX_COLORS = 256
  Buffer::DEFAULT_CAPACITY
  ```

### Enum Values
- **Format:** `lowercase` or `PascalCase`
- **Termisu convention:** `lowercase` for simple enums
- **Examples:**
  ```crystal
  enum Color
    red
    green
    blue
  end

  enum Key
    Escape
    Enter
    Space
  end
  ```

### Type Variables
- **Format:** `PascalCase` starting with `T`
- **Examples:** `T`, `T1`, `T2`

## Code Formatting

### Indentation
- **Spaces:** 2 spaces (NO tabs)
- **Example:**
  ```crystal
  def render
    buffer.each do |cell|
      if cell.changed?
        renderer.write(cell)
      end
    end
  end
  ```

### Line Length
- **Preferred:** Under 100 characters
- **Hard limit:** 120 characters

### Spacing
- **Around operators:** Single space
- **After commas:** Single space
- **No space:** Inside parentheses, brackets
- **Examples:**
  ```crystal
  x = 1 + 2
  array = [1, 2, 3]
  func(arg1, arg2)
  hash = {"key" => "value"}
  ```

### Blank Lines
- **One blank line:** Between methods, after `require` statements
- **Two blank lines:** Between class/module definitions

## Method Definitions

### Order
1. `public` methods
2. `protected` methods
3. `private` methods

### Signatures
```crystal
# Good: Explicit types
def set_cell(x : Int32, y : Int32, char : Char, fg : Color? = nil, bg : Color? = nil) : Nil
  @buffer[y][x] = Cell.new(char, fg, bg)
end

# Bad: Missing types
def set_cell(x, y, char, fg = nil, bg = nil)
  @buffer[y][x] = Cell.new(char, fg, bg)
end
```

### Keyword Arguments
```crystal
# Preferred for clarity
def create_buffer(width : Int32, height : Int32, sync : Bool = false) : Buffer
  Buffer.new(width, height, sync_updates: sync)
end
```

## Class Structure

### Canonical Order
```crystal
require "dependencies"

class Termisu::ClassName
  # 1. Constants
  DEFAULT_SIZE = 80

  # 2. Enum definitions (if nested)
  enum Status
    Ready
    Running
  end

  # 3. Nested classes/structs
  struct Config
    property size : Int32
  end

  # 4. Class variables
  @@instance_count = 0

  # 5. Class methods
  def self.create : self
    new
  end

  # 6. Constructor
  def initialize(@size : Int32 = DEFAULT_SIZE)
  end

  # 7. Property macros
  property size : Int32
  getter status : Status
  private_setter running : Bool

  # 8. Instance methods
  def start : Nil
  end

  # 9. Protected methods
  protected def internal_method : Nil
  end

  # 10. Private methods
  private def helper : Nil
  end
end
```

## Blocks and Procs

### Single-line blocks
```crystal
# Prefer braces for single line
[1, 2, 3].map { |x| x * 2 }
```

### Multi-line blocks
```crystal
# Prefer do/end for multi-line
[1, 2, 3].each do |x|
  puts x
  puts x * 2
end
```

### Proc type syntax
```crystal
# Explicit proc types
callback : Proc(Int32, Int32, String)
draw_text : ->(x : Int32, y : Int32, text : String)

# With return type
processor : Proc(String, Int32)
```

## Error Handling

### Custom exceptions
```crystal
class Termisu::Error < Exception
end

class Termisu::ParseError < Error
  getter line_number : Int32

  def initialize(message : String, @line_number : Int32)
    super("#{message} at line #{@line_number}")
  end
end
```

### Raise vs return
```crystal
# Raise for exceptional conditions
def connect(url : String) : Connection
  raise Error.new("Invalid URL") unless url.valid?
  Connection.new(url)
end

# Return nil for expected failures
def connect?(url : String) : Connection?
  return nil unless url.valid?
  Connection.new(url)
end
```

## Comments

### Public API comments
```crystal
# Polls for events with optional timeout.
#
# Parameters:
# - `timeout`: Maximum time to wait in milliseconds. Pass `nil` to block indefinitely.
#
# Returns `Event::Any` if an event occurred, `nil` on timeout.
#
# ```
# termisu.poll_event(100) # 100ms timeout
# termisu.poll_event       # Block forever
# ```
def poll_event(timeout : Int32? = nil) : Event::Any?
end
```

### Inline comments
```crystal
# Check cache first to avoid redundant work
if @cached_value
  return @cached_value
end

# Fall back to expensive computation
@cached_value = compute_expensive_value
```

### TODO/FIXME
```crystal
# TODO: Add support for Unicode combining characters
# FIXME: This may leak file descriptors on error
```

## Type Annotations

### Public methods: Always annotate
```crystal
def public_method(x : Int32) : String
  x.to_s
end
```

### Private methods: May omit
```crystal
private def helper(x)
  x.to_s
end
```

### Local variables: Omit
```crystal
# Good
result = compute()

# Also acceptable (when type not obvious)
result : String = compute()
```

## Null Handling

### Prefer union types over nil checks
```crystal
# Good
def set_color(color : Color?) : Nil
  @color = color || Color.default
end

# Better: nilable union
def set_color(color : Color?) : Nil
  return unless color
  @color = color
end
```

### Try operator for safe navigation
```crystal
# Good: Returns nil if config is nil
size = config.try(&.size) || DEFAULT_SIZE

# Good: Conditional method call
terminal.try(&.flush)
```

## Struct vs Class

### Use Struct when:
- Value semantics (copy on assignment)
- Small, immutable data
- Performance critical

```crystal
struct Cell
  getter char : Char
  getter fg : Color?
  getter bg : Color?

  def initialize(@char, @fg = nil, @bg = nil)
  end
end
```

### Use Class when:
- Reference semantics needed
- Mutable state
- Inheritance required
- Resource cleanup (finalize)

```crystal
class Terminal
  def initialize
    @buffer = Buffer.new
  end

  def finalize
    @buffer.close
  end
end
```

## Generics

### Type parameters
```crystal
class Channel(T)
  def send(value : T) : Nil
    @queue.push(value)
  end

  def receive : T
    @queue.pop
  end
end
```

### Constraints
```crystal
def process(item : Number) : Number
  item * 2
end

class Container(T)
  # T must respond to `to_s`
  def to_s_array(items : Array(T)) : Array(String)
    items.map(&.to_s)
  end
end
```

## Operator Overloading

```crystal
struct Point
  def +(other : Point) : Point
    Point.new(@x + other.x, @y + other.y)
  end

  def <=>(other : Point) : Int32
    @x <=> other.x
  end
end
```

## Macro Usage

### For boilerplate reduction
```crystal
macro property(name, type)
  def {{name}} : {{type}}
    @{{name}}
  end

  def {{name}}=(value : {{type}}) : Nil
    @{{name}} = value
  end
end

property size, Int32
```

### For type-safe delegates
```crystal
macro delegate(method, to)
  def {{method}}(*args)
    {{to}}.{{method}}(*args)
  end
end
```

## Import Conventions

### Project imports
```crystal
# Use relative path for project files
require "../spec_helper"
require "./termisu/buffer"

# Use full path after shard install
require "termisu"
```

### Standard library
```crystal
require "io"
require "enum"
```

## Formatted Code Check

Always run formatter before committing:
```bash
crystal tool format

# Check without modifying
crystal tool format --check

# Via Hace
bin/hace format
bin/hace format:check
```
