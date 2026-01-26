# Terminal Mode Patterns

Patterns for terminal mode handling in Termisu TUI development.

## When to Use

- "Switch terminal modes"
- "Shell-out from TUI"
- "Password input"
- "Handle Ctrl+C"
- "Restore terminal state"

## Mode Overview

Termisu supports multiple terminal modes for different scenarios:

| Mode | Behavior | Use Case |
|------|----------|----------|
| `raw` | No processing, char-by-char, no echo, no signals | Full TUI control (default) |
| `cooked` | Line buffering, echo, signals enabled | Shell-out, external programs |
| `cbreak` | Char-by-char with echo and signals | Interactive prompts |
| `password` | Line buffering, no echo | Secure password entry |
| `semi_raw` | Char-by-char with signals (Ctrl+C works) | TUI with graceful exit |
| `full_cooked` | Full terminal driver processing | Complete shell emulation |

## Core Pattern: RAII Resource Management

**CRITICAL:** Always use `begin/ensure` for terminal restoration.

```crystal
termisu = Termisu.new

begin
  # TUI logic here
ensure
  termisu.close  # ALWAYS RESTORE
end
```

**Why:** If your code crashes (e.g., unhandled exception), the terminal
will be left in a broken state (no echo, weird characters). The `ensure`
block guarantees restoration even on crash.

## Shell-out Pattern (Recommended)

**Scenario:** User wants to run `vim` or other external program from TUI.

```crystal
termisu.suspend do
  # - Exits alternate screen
  # - Enables cooked mode
  # - Restores normal terminal behavior
  system("vim file.txt")
  # - TUI fully restored on block exit
end
```

**Benefits:**
- Automatic cleanup
- Works even if system() raises
- Terminal state fully restored

**Manual Shell-out (not recommended):**
```crystal
termisu.alternate_screen(false)
termisu.cooked_mode
begin
  system("vim file.txt")
ensure
  termisu.alternate_screen(true)
  termisu.raw_mode
  termisu.sync  # Full redraw needed
end
```

## Password Input Pattern

**Scenario:** Get password without showing characters.

```crystal
password = termisu.with_password_mode do
  print "Password: "
  gets.try(&.chomp)
end
# TUI fully restored
```

**What happens:**
1. Exit alternate screen (if active)
2. Enable password mode (line buffering, no echo)
3. User types (hidden)
4. On block exit: restore TUI state

## Custom Mode Patterns

### Semi-Raw Mode (Ctrl+C Works)

```crystal
termisu.with_mode(Termisu::Terminal::Mode.semi_raw) do
  # Char-by-char input
  # Signals enabled (Ctrl+C works)
  # Useful for TUI that should allow graceful exit
end
```

### Cbreak Mode (Interactive Prompt)

```crystal
termisu.with_cbreak_mode(preserve_screen: false) do
  # Char-by-char with echo
  # Signals enabled
  # Good for "Press any key" prompts
end
```

### Mode Combinations

```crystal
# Create custom mode: char-by-char with echo but no signals
custom_mode = Termisu::Terminal::Mode::Echo
termisu.with_mode(custom_mode) do
  # Custom input handling
end
```

## Mode Detection

```crystal
# Check current mode
if termisu.raw_mode?
  puts "In raw mode"
end

if termisu.alternate_screen?
  puts "Alternate screen active"
end

# Get current mode flags
current = termisu.current_mode
if current
  puts "Mode: #{current}"
end
```

## Mode Change Events

**Subscribe to mode changes:**

```crystal
termisu.each_event do |event|
  case event
  when Termisu::Event::ModeChange
    puts "Mode: #{event.previous_mode} -> #{event.mode}"
    puts "Reason: #{event.reason}"
  when Termisu::Event::Key
    break if event.key.escape?
  end
end
```

**Event fields:**
- `event.mode` - New mode
- `event.previous_mode` - Previous mode
- `event.reason` - Why the change happened

## Common Pitfalls

### 1. Forgetting ensure Block

**WRONG:**
```crystal
termisu = Termisu.new
termisu.raw_mode  # If this crashes...
# ...do stuff
termisu.close     # ...this never runs!
```

**CORRECT:**
```crystal
termisu = Termisu.new
begin
  termisu.raw_mode
  # ...do stuff
ensure
  termisu.close  # Always runs
end
```

### 2. Nested Mode Switches

**Be careful with nested suspend:**

```crystal
termisu.suspend do
  # In cooked mode now
  system("vim", file)

  # Don't do this:
  # termisu.suspend { ... }  # Double suspend = wrong state

  # Do this instead:
  system("less", file)  # Just run another command
end
```

### 3. Forgetting sync After Mode Switch

**After any mode change, always redraw:**

```crystal
termisu.with_cbreak_mode do
  # User interaction
end
termisu.sync  # FULL REDRAW - state may be corrupted
```

### 4. Getting Input in Wrong Mode

**Raw mode (TUI default):**
```crystal
# In raw mode, use termisu input:
event = termisu.poll_event
```

**Cooked mode (shell-out):**
```crystal
termisu.suspend do
  # In cooked mode, use normal IO:
  input = gets
end
```

## Signal Handling Patterns

### Allow Ctrl+C Exit (Semi-Raw)

```crystal
termisu.with_mode(Termisu::Terminal::Mode.semi_raw) do
  loop do
    case event = termisu.poll_event
    when Termisu::Event::Key
      break if event.key.escape?
      # Ctrl+C generates SIGINT, handled by system
    when Termisu::Event::Tick
      # Animation
    end
  end
end
```

### Trap Signals Yourself

```crystal
# In raw mode, signals are disabled by default
# Handle graceful shutdown:
trap("SIGINT") do
  puts "\nShutting down..."
  termisu.close
  exit(0)
end
```

## Mode State Diagram

```
Initial
   ↓
[Initialize Termisu]
   ↓
Raw Mode (default for TUI)
   ↓
┌─────────────┬──────────────┬──────────────┐
│             │              │              │
suspend()   with_mode()   with_*mode()  Manual change
│             │              │              │
↓             ↓              ↓              ↓
Cooked      Custom        Cbreak/Password   Any
│             │              │              │
└─────────────┴──────────────┴──────────────┘
                    ↓
              [Block Exit]
                    ↓
              Restore Previous
```

## Testing Mode Switches

```crystal
it "restores terminal on exception" do
  terminal = CaptureTerminal.new
  terminal.raw_mode

  begin
    raise "boom"
  ensure
    terminal.close
  end

  terminal.raw_mode?.should be_false
end
```

## Quick Reference

| Task | Pattern |
|------|---------|
| Initialize TUI | `Termisu.new` + `ensure close` |
| Run external command | `termisu.suspend { system(...) }` |
| Get password | `termisu.with_password_mode { gets }` |
| Enable Ctrl+C | `termisu.with_mode(Mode.semi_raw) { ... }` |
| Interactive prompt | `termisu.with_cbreak_mode { ... }` |
| Custom mode | `termisu.with_mode(flags) { ... }` |
| Check current mode | `termisu.raw_mode?`, `termisu.current_mode` |
| Redraw after switch | `termisu.sync` (full redraw) |
| Mode change events | `when Termisu::Event::ModeChange` |

## Best Practices

1. **Always use ensure blocks** for terminal restoration
2. **Prefer suspend()** for shell-out (automatic state management)
3. **Always sync()** after mode switches (full redraw)
4. **Use semi_raw** if you want Ctrl+C to work
5. **Never mix** raw mode input with `gets`/`readline`
6. **Test crashes** - ensure terminal restores on exception
7. **Check mode** before assuming input behavior
