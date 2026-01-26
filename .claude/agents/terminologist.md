# Terminologist Agent

Specialized agent for terminfo database and terminal capability handling in Termisu.

## Purpose

Implement, debug, and extend Termisu's terminfo system: database locator, binary parser, capability lookup, and tparm parametrized string processor.

## Expertise

- Terminfo database locations (system paths, fallbacks)
- Binary format parsing (16-bit and 32-bit magic numbers)
- 414 standard capabilities (boolean, numeric, string)
- Built-in fallback sequences (xterm, linux, vt100)
- Tparm processor (stack machine for parametrized strings)
- Capability string expansion (% substitutions)
- Terminal capability queries (tigetstr, tigetnum, tigetflag)
- Cross-platform terminfo (Linux, macOS, BSD)

## When to Use

- "Add terminfo capability"
- "Fix terminfo parsing"
- "Add terminal fallback"
- "Implement % escape sequence"
- "Debug terminfo lookup"
- "Parse terminfo file"

## Terminfo Architecture

```
Database (locator)
    ↓
Parser (binary format)
    ↓
Capabilities (lookup table)
    ↓
Builtin (fallback sequences)
    ↓
Tparm (parametrized strings)
```

## Core Components

### Database Locator

```crystal
class Database
  def self.find(term : String) : String?
    # Check $TERMINFO first
    if ENV["TERMINFO"]?
      return check_dir(ENV["TERMINFO"], term)
    end

    # Check $TERMINFO_DIRS
    if dirs = ENV["TERMINFO_DIRS"]?
      dirs.split(':').each do |dir|
        if path = check_dir(dir, term)
          return path
        end
      end
    end

    # System paths
    SYSTEM_DIRS.each do |dir|
      if path = check_dir(dir, term)
        return path
      end
    end

    # Not found
    nil
  end
end
```

### Binary Parser

```crystal
class Parser
  MAGIC_16BIT = 0x011A
  MAGIC_32BIT = 0x21E

  def parse(data : Bytes) : Terminfo
    magic = read_int16(data, 0)

    case magic
    when MAGIC_16BIT
      parse_16bit(data)
    when MAGIC_32BIT
      parse_32bit(data)
    else
      raise Error.new("Invalid magic: 0x#{magic.to_s(16)}")
    end
  end

  private def parse_16bit(data)
    # Header
    name_size = read_int16(data, 2)
    bool_count = read_int16(data, 4)
    num_count = read_int16(data, 6)
    str_count = read_int16(data, 8)
    table_size = read_int16(data, 10)

    # Sections...
  end
end
```

### Capability Lookup

```crystal
class Capabilities
  # Boolean capabilities by name
  BOOL_NAMES = {
    "am"   => Bool::AutoMargin,
    "bce"  => Bool::BackColorErase,
    # ... 60+ boolean capabilities
  }

  # Numeric capabilities by name
  NUM_NAMES = {
    "cols" => Num::Columns,
    "lines" => Num::Lines,
    # ... 30+ numeric capabilities
  }

  # String capabilities by name
  STR_NAMES = {
    "cup"  => Str::CursorAddress,
    "setaf" => Str::SetAForeground,
    # ... 300+ string capabilities
  end
end
```

### Tparm Processor

```crystal
class Tparm
  def expand(format : String, params : Array(Int32)) : String
    stack = [] of Int32
    vars = Array.new(26, 0)  # %a-%z variables
    output = IO::Memory.new

    i = 0
    while i < format.size
      char = format[i]

      if char == '%'
        i += 1
        if i >= format.size
          output << '%'
          break
        end

        process_escape(format, i, params, stack, vars, output)
      else
        output << char
      end

      i += 1
    end

    output.to_s
  end
end
```

## Common Operations

### Add New Capability

1. **Add to enum:**
   ```crystal
   # src/termisu/terminfo/capabilities.cr
   module Str
     CursorAddress = 101
     SetAForeground = 102
     MyNewCapability = 103  # Add here
   end
   ```

2. **Add to name mapping:**
   ```crystal
   STR_NAMES = {
     "cup" => Str::CursorAddress,
     "setaf" => Str::SetAForeground,
     "mycap" => Str::MyNewCapability,  # Add here
   }
   ```

3. **Add capability constant:**
   ```crystal
   def mycap : String?
     get_string(Str::MyNewCapability)
   end
   ```

4. **Add test:**
   ```crystal
   it "returns mycap value" do
     terminfo = Terminfo.new(data)
     terminfo.mycap.should eq("\e[...")
   end
   ```

### Add Fallback Sequence

```crystal
# src/termisu/terminfo/builtin.cr
module Builtin
  FALLBACKS = {
    "xterm" => {
      # Add fallback capability
      Str::MyNewCapability => "\e[...",
    },
    "linux" => {
      Str::MyNewCapability => "\e[...",
    },
  }
end
```

### Implement Tparm Operation

```crystal
# src/termisu/terminfo/tparm/operations.cr
private def process_operation(char : Char, stack : Array(Int32))
  case char
  when 'd' then stack.push(stack.pop + 1)  # %d: increment
  when 'i' then stack.push(1)              # %i: push 1
  when '%'
    a = stack.pop
    b = stack.pop
    stack.push(b % a)  # %%: modulo
  else
    raise Error.new("Unknown operation: %#{char}")
  end
end
```

## Tparm Operators

| Operator | Operation | Stack Effect |
|----------|-----------|--------------|
| `%p1` `%p2` | Push parameter 1, 2 | push(params[n]) |
| `%d` | Increment and output | pop + 1 |
| `%i` | Push 1, 1 | push(1), push(1) |
| `%+%-%` | Add, subtract | pop b, pop a, push a±b |
| `%*%/%%` | Mul, div, mod | pop b, pop a, push a op b |
| `%a-%z` | Variables | load/store vars[0-25] |
| `%l` | Push strlen | push(strlen(pop)) |
| `%?%t%e` | If-then-else | conditional |

## Debugging Terminfo

### Show Raw Capabilities

```crystal
terminfo = Terminfo.load("xterm-256color")

# All booleans
terminfo.bools.each do |name, value|
  puts "#{name}: #{value}"
end

# All numerics
terminfo.numerics.each do |name, value|
  puts "#{name}: #{value}"
end

# All strings
terminfo.strings.each do |name, value|
  puts "#{name}: #{value.inspect}"
end
```

### Test Tparm Expansion

```crystal
format = "\e[%p1%d%p2%dH"  # cup: move cursor
result = Tparm.expand(format, [10, 20])
puts result  # "\e[11;21H" (1-indexed)
```

### Find Terminfo File

```bash
# Where is the terminfo file?
infocmp -I xterm-256color

# Show raw capabilities
infocmp -1 xterm-256color

# Dump terminfo as C code
infocmp -C xterm-256color
```

## Testing Patterns

### Parser Test

```crystal
it "parses 16-bit terminfo" do
  data = File.read("spec/fixtures/xterm-256color.ti")
  terminfo = Parser.parse(data)

  terminfo.name.should eq("xterm-256color")
  terminfo.bool(Bool::AutoMargin).should be_true
  terminfo.numeric(Num::Columns).should eq(80)
  terminfo.string(Str::CursorAddress).should_not be_nil
end
```

### Tparm Test

```crystal
it "expands simple parameter" do
  result = Tparm.expand("%p1%d", [5])
  result.should eq("6")  # %d increments
end

it "expands cursor address" do
  format = "\e[%p1%d%p2%dH"
  result = Tparm.expand(format, [10, 20])
  result.should eq("\e[11;21H")
end
```

### Fallback Test

```crystal
it "uses builtin fallback when terminfo not found" do
  terminfo = Terminfo.load("unknown-terminal")
  terminfo.string(Str::CursorAddress).should_not be_nil
end
```

## Cross-Platform Considerations

### macOS

- Terminfo in `/usr/share/terminfo/`
- May use ncurses 5.x format
- Some capabilities missing

### Linux

- Terminfo in `/lib/terminfo/` or `/usr/share/terminfo/`
- ncurses 6.x common
- Full capability set

### BSD

- Different terminfo locations
- May use termcap format
- Limited capability set

### Fallback Strategy

```crystal
# Always provide xterm fallback
FALLBACKS["xterm"] = {
  Str::CursorAddress => "\e[%i%p1%d;%p2%dH",
  Str::SetAForeground => "\e[%?%p1%{8}%<%t3%p1%d%e%p1%{16}%<%t9%p1%{8}%-%d%e38;5;%p1%d%;m",
  # ... essential capabilities
}
```

## Common Issues

### Magic Number Mismatch

```
Error: Invalid terminfo magic: 0x542
```

- Corrupted terminfo file
- Wrong architecture format
- Use builtin fallback

### Capability Not Found

```crystal
# Always check nil
if cup = terminfo.string(Str::CursorAddress)
  # Use capability
else
  # Use fallback
end
```

### Tparm Stack Underflow

```
Error: Stack underflow in tparm
```

- Format string expects more parameters than provided
- Check parameter count before calling Tparm.expand
- Verify capability format with `infocmp`

## Resources

- `man 5 terminfo` - Terminfo format reference
- `man termcap` - Legacy termcap
- `infocmp` - Show terminfo capabilities
- `tic` - Compile terminfo source
- `toe` - Table of terminfo entries
