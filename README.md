# Termisu


[![Crystal Version](https://img.shields.io/badge/Crystal-%3E%3D1.18.2-000000?style=flat&labelColor=24292e&color=000000&logo=crystal&logoColor=white)](https://crystal-lang.org/)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue?style=flat&labelColor=24292e&logo=opensourceinitiative&logoColor=white)](LICENSE)
[![Tests](https://img.shields.io/github/actions/workflow/status/omarluq/termisu/test.yml?style=flat&labelColor=24292e&label=Tests&logo=github&logoColor=white)](https://github.com/omarluq/termisu/actions/workflows/test.yml)
[![Version](https://img.shields.io/github/release/omarluq/termisu?style=flat&labelColor=24292e&color=28a745&label=Version&logo=semver&logoColor=white)](https://github.com/omarluq/termisu/releases)\
[![codecov](https://img.shields.io/codecov/c/github/omarluq/termisu?style=flat&labelColor=24292e&logo=codecov&logoColor=white&token=YW23EDL5T5)](https://codecov.io/gh/omarluq/termisu)
[![Docs](https://img.shields.io/badge/Docs-API%20Reference-5e5086?style=flat&labelColor=24292e&logo=gitbook&logoColor=white)](https://omarluq.github.io/termisu/)
[![Maintained](https://img.shields.io/badge/Maintained%3F-yes-28a745?style=flat&labelColor=24292e&logo=checkmarx&logoColor=white)](https://github.com/omarluq/termisu)
[![Made with Love](https://img.shields.io/badge/Made%20with-Love-ff69b4?style=flat&labelColor=24292e&logo=githubsponsors&logoColor=white)](https://github.com/omarluq/termisu)
<!--  [![All Contributors](https://img.shields.io/github/all-contributors/omarluq/termisu?style=flat&labelColor=24292e&color=7f8c8d)](https://github.com/omarluq/termisu/graphs/contributors)-->

<img src="assets/termisu.png" align="right" alt="Termisu Logo" width="200"/>

Termisu _(/ˌtɛr.mɪˈsuː/ — like tiramisu, but for terminals)_ is a library that provides a sweet and minimalistic API for writing text-based user interfaces in pure Crystal. It offers an abstraction layer over terminal capabilities through cell-based rendering with double buffering, allowing efficient and flicker-free TUI development. The API is intentionally small and focused, making it easy to learn, test, and maintain. Inspired by termbox, Termisu brings similar simplicity and elegance to the Crystal ecosystem.

> [!WARNING]
> Termisu is still in development and is considered unstable. The API is subject to change, and you may encounter bugs or incomplete features.
> Use it at your own risk, and contribute by reporting issues or suggesting improvements!

## Installation

1. Add the dependency to your `shard.yml`:

```yaml
dependencies:
  termisu:
    github: omarluq/termisu
```

2. Run `shards install`

## Usage

```crystal
require "termisu"

termisu = Termisu.new

begin
  # Set cells with colors and attributes
  termisu.set_cell(0, 0, 'H', fg: Termisu::Color.red, attr: Termisu::Attribute::Bold)
  termisu.set_cell(1, 0, 'i', fg: Termisu::Color.green)
  termisu.set_cursor(2, 0)
  termisu.render

  # Event loop with keyboard and mouse support
  termisu.enable_mouse
  loop do
    if event = termisu.poll_event(100)
      case event
      when Termisu::Event::Key
        break if event.key.escape?
        break if event.key.lower_q?
      when Termisu::Event::Mouse
        termisu.set_cell(event.x, event.y, '*', fg: Termisu::Color.cyan)
        termisu.render
      end
    end
  end
ensure
  termisu.close
end
```

See `examples/` for complete demonstrations:

- `showcase.cr` - Colors, attributes, and input handling
- `animation.cr` - Timer-based animation with async events

![Termisu Showcase](assets/demo-screenshot.png)

## API

### Initialization

```crystal
termisu = Termisu.new  # Enters raw mode + alternate screen
termisu.close          # Cleanup (always call in ensure block)
```

### Terminal

```crystal
termisu.size                  # => {width, height}
termisu.alternate_screen?     # => true/false
termisu.raw_mode?             # => true/false
termisu.current_mode          # => Mode flags or nil
```

### Cell Buffer

```crystal
termisu.set_cell(x, y, 'A', fg: Color.red, bg: Color.black, attr: Termisu::Attribute::Bold)
termisu.clear                 # Clear buffer
termisu.render                # Apply changes (diff-based)
termisu.sync                  # Force full redraw
```

### Cursor

```crystal
termisu.set_cursor(x, y)
termisu.hide_cursor
termisu.show_cursor
```

### Events

```crystal
# Blocking
event = termisu.poll_event                # Block until event
event = termisu.wait_event                # Alias

# With timeout
event = termisu.poll_event(100)           # Timeout (ms), nil on timeout
event = termisu.poll_event(100.milliseconds)

# Non-blocking (select/else pattern)
event = termisu.try_poll_event            # Returns nil immediately if no event

# Iterator
termisu.each_event do |event|
  case event
  when Termisu::Event::Key        then # keyboard
  when Termisu::Event::Mouse      then # mouse click/move
  when Termisu::Event::Resize     then # terminal resized
  when Termisu::Event::Tick       then # timer tick (if enabled)
  when Termisu::Event::ModeChange then # mode switched
  end
end
```

### Event Types

`Event::Any` is the union type: `Event::Key | Event::Mouse | Event::Resize | Event::Tick | Event::ModeChange`

```crystal
# Event::Key - Keyboard input
event.key                          # => Input::Key
event.char                         # => Char?
event.modifiers                    # => Input::Modifier
event.ctrl? / event.alt? / event.shift? / event.meta?

# Event::Mouse - Mouse input
event.x, event.y                   # Position (1-based)
event.button                       # => Mouse::Button
event.motion?                      # Mouse moved while button held
event.press?                       # Button press (not release/motion)
event.wheel?                       # Scroll wheel event
event.ctrl? / event.alt? / event.shift?

# Mouse::Button enum
event.button.left?
event.button.middle?
event.button.right?
event.button.release?
event.button.wheel_up?
event.button.wheel_down?

# Event::Resize - Terminal resized
event.width, event.height          # New dimensions
event.old_width, event.old_height  # Previous (nil if unknown)
event.changed?                     # Dimensions changed?

# Event::Tick - Timer tick (for animations)
event.frame                        # Frame counter (UInt64)
event.elapsed                      # Time since timer started
event.delta                        # Time since last tick
event.missed_ticks                 # Ticks missed due to slow processing (UInt64)

# Event::ModeChange - Terminal mode changed
event.mode                         # New mode (Terminal::Mode)
event.previous_mode                # Previous mode (Terminal::Mode?)
event.changed?                     # Did mode actually change?
event.to_raw?                      # Transitioning to raw mode?
event.from_raw?                    # Transitioning from raw mode?
event.to_user_interactive?         # Entering canonical/echo mode?
event.from_user_interactive?       # Leaving canonical/echo mode?
```

### Mouse & Keyboard

```crystal
termisu.enable_mouse               # Enable mouse tracking
termisu.disable_mouse
termisu.mouse_enabled?

termisu.enable_enhanced_keyboard   # Kitty protocol (Tab vs Ctrl+I)
termisu.disable_enhanced_keyboard
termisu.enhanced_keyboard?
```

### Timer (for animations)

```crystal
# Sleep-based timer (portable, good for most use cases)
termisu.enable_timer(16.milliseconds)    # ~60 FPS tick events

# Kernel-level timer (Linux timerfd/epoll, macOS kqueue)
# More precise timing, better for high frame rates
termisu.enable_system_timer(16.milliseconds)

termisu.disable_timer                    # Disable either timer type
termisu.timer_enabled?
termisu.timer_interval = 8.milliseconds  # Change interval at runtime
```

#### Timer Comparison

| Feature | Timer (sleep) | SystemTimer (kernel) |
|---------|---------------|----------------------|
| Mechanism | `sleep` in fiber | timerfd/epoll (Linux), kqueue (macOS) |
| Precision | ~1-2ms jitter | Sub-millisecond |
| Max FPS | ~48 FPS reliable | ~90 FPS reliable |
| Missed tick detection | No | Yes (`event.missed_ticks`) |
| Portability | All platforms | Linux, macOS, BSD |
| Best for | Simple animations, low FPS | Games, smooth animations |

#### Benchmark Results

| Target FPS | Target Interval | Timer (sleep) | SystemTimer (kernel) | Notes |
|------------|-----------------|---------------|----------------------|-------|
| 30 | 33ms | ⚠️ 41ms (~24 FPS) | ✅ 33ms (~30 FPS) | Sleep overshoots |
| 60 | 16ms | ⚠️ 21ms (~48 FPS) | ✅ 17ms (~60 FPS) | Sleep hits ~21ms floor |
| 90 | 11ms | ⚠️ 21ms (~48 FPS) | ✅ 11ms (~90 FPS) | Sleep stuck at floor |
| 120 | 8ms | ⚠️ 11ms (~91 FPS) | ⚠️ 11ms (~91 FPS) | Both hit I/O ceiling |
| 144 | 7ms | ⚠️ 11ms (~91 FPS) | ⚠️ 11ms (~91 FPS) | Same ceiling |

**Key Findings:**
- **SystemTimer accuracy:** Kernel timers hit target intervals precisely up to ~90 FPS
- **Sleep timer quirks:** Has a ~21ms floor at mid-range targets, overshoots at low FPS
- **Terminal I/O ceiling:** Both timers cap at ~91 FPS (~11ms) due to render/flush overhead
- **Missed ticks:** SystemTimer detects and reports frame drops via `missed_ticks` field

**Open Questions:**
- Why does sleep timer overshoot at 30 FPS (41ms vs 33ms target)?
- Can terminal I/O be batched more aggressively to push the ~91 FPS ceiling higher?
- Would async rendering with double-buffered I/O help reduce the ~11ms floor?

### Terminal Modes

Temporarily switch terminal modes for shell-out, password input, or custom I/O.
Mode changes emit `Event::ModeChange` events and automatically coordinate with the event loop.

```crystal
# Shell-out: Exit TUI, run shell commands, return seamlessly
termisu.with_cooked_mode(preserve_screen: false) do
  puts "You're in the normal terminal!"
  system("vim file.txt")
end
# TUI automatically restored with full redraw

# Suspend alias (same as with_cooked_mode, preserve_screen: false)
termisu.suspend do
  system("git commit")
end

# Password input: Hidden typing (no echo)
termisu.with_password_mode do
  print "Password: "
  password = gets.try(&.chomp)
end

# Cbreak mode: Character-by-character with echo (Ctrl+C works)
termisu.with_cbreak_mode do
  print "Press any key: "
  char = STDIN.read_char
end

# Custom mode with specific flags
custom = Termisu::Terminal::Mode::Echo | Termisu::Terminal::Mode::Signals
termisu.with_mode(custom, preserve_screen: true) do
  # Your custom mode code
end

# Check current mode
termisu.current_mode  # => Mode flags or nil (raw mode)
```

#### Mode Flags

Individual flags map to POSIX termios settings:

```crystal
Termisu::Terminal::Mode::None             # Raw mode (no processing)
Termisu::Terminal::Mode::Canonical        # Line-buffered input (ICANON)
Termisu::Terminal::Mode::Echo             # Echo typed characters (ECHO)
Termisu::Terminal::Mode::Signals          # Ctrl+C/Z signals (ISIG)
Termisu::Terminal::Mode::Extended         # Extended input processing (IEXTEN)
Termisu::Terminal::Mode::FlowControl      # XON/XOFF flow control (IXON)
Termisu::Terminal::Mode::OutputProcessing # Output processing (OPOST)
Termisu::Terminal::Mode::CrToNl           # CR to NL translation (ICRNL)

# Combine flags with |
custom = Mode::Echo | Mode::Signals
```

#### Mode Presets

```crystal
Mode.raw         # Full TUI control
Mode.cbreak      # Char-by-char with feedback
Mode.cooked      # Shell-out, external programs
Mode.full_cooked # Complete shell emulation
Mode.password    # Secure input (no echo)
Mode.semi_raw    # TUI with Ctrl+C support
```

| Preset     | Canonical | Echo | Signals | Use Case                     |
|------------|-----------|------|---------|------------------------------|
| raw        | -         | -    | -       | Full TUI control             |
| cbreak     | -         | ✓    | ✓       | Char-by-char with feedback   |
| cooked     | ✓         | ✓    | ✓       | Shell-out, external programs |
| full_cooked| ✓         | ✓    | ✓       | Complete shell emulation     |
| password   | ✓         | -    | ✓       | Secure text entry            |
| semi_raw   | -         | -    | ✓       | TUI with Ctrl+C support      |

#### Convenience Methods

```crystal
termisu.with_cooked_mode { }      # Shell-out mode
termisu.with_cbreak_mode { }      # Char-by-char with echo
termisu.with_password_mode { }    # Hidden input
termisu.suspend { }               # Alias for with_cooked_mode(preserve_screen: false)
termisu.with_mode(mode) { }       # Custom mode
```

#### Options

- `preserve_screen: true` - Stay in alternate screen (overlay mode)
- `preserve_screen: false` - Exit alternate screen (shell-out mode)

### Colors

```crystal
Color.red, Color.green, Color.blue       # ANSI-8
Color.bright_red, Color.bright_green     # Bright variants
Color.ansi256(208)                       # 256-color palette
Color.rgb(255, 128, 64)                  # TrueColor
Color.from_hex("#FF8040")                # Hex string
Color.grayscale(12)                      # Grayscale (0-23)

color.to_rgb                             # Convert to RGB
color.to_ansi256                         # Convert to 256
color.to_ansi8                           # Convert to 8
```

### Attributes

```crystal
Termisu::Attribute::None
Termisu::Attribute::Bold
Termisu::Attribute::Dim
Termisu::Attribute::Cursive      # Italic
Termisu::Attribute::Italic       # Alias for Cursive
Termisu::Attribute::Underline
Termisu::Attribute::Blink
Termisu::Attribute::Reverse
Termisu::Attribute::Hidden
Termisu::Attribute::Strikethrough

# Combine with |
attr = Termisu::Attribute::Bold | Termisu::Attribute::Underline
strike = Termisu::Attribute::Strikethrough | Termisu::Attribute::Dim
```

### Keys

```crystal
# Key event properties
case event
when Termisu::Event::Key
  event.key                      # => Input::Key enum
  event.char                     # => Char? (printable character)
  event.modifiers                # => Input::Modifier flags
end

# Modifier checks (on Event::Key)
event.ctrl?                      # Ctrl held
event.alt?                       # Alt/Option held
event.shift?                     # Shift held
event.meta?                      # Meta/Super/Windows held

# Common shortcuts
event.ctrl_c?
event.ctrl_d?
event.ctrl_q?
event.ctrl_z?

# Check for any modifier
event.modifiers.none?            # No modifiers held
event.modifiers.ctrl?            # Direct modifier check
event.modifiers & Input::Modifier::Ctrl  # Bitwise check

# Key matching - Special keys
event.key.escape?
event.key.enter?
event.key.tab?
event.key.back_tab?              # Shift+Tab
event.key.backspace?
event.key.space?
event.key.delete?
event.key.insert?

# Key matching - Arrow keys
event.key.up?
event.key.down?
event.key.left?
event.key.right?

# Key matching - Navigation
event.key.home?
event.key.end?
event.key.page_up?
event.key.page_down?

# Key matching - Function keys (F1-F24)
event.key.f1?
event.key.f12?

# Key matching - Letters
event.key.q?                     # Case-insensitive (a? - z?)
event.key.lower_q?               # Case-sensitive lowercase
event.key.upper_q?               # Case-sensitive uppercase

# Key matching - Numbers
event.key.num_0?                 # num_0? - num_9?

# Key predicates
event.key.letter?                # A-Z or a-z
event.key.digit?                 # 0-9
event.key.function_key?          # F1-F24
event.key.navigation?            # Arrows + Home/End/PageUp/PageDown
event.key.printable?             # Has character representation
event.key.to_char                # => Char? for printable keys
```

### Modifiers

```crystal
Input::Modifier::None
Input::Modifier::Shift
Input::Modifier::Alt             # Alt/Option
Input::Modifier::Ctrl
Input::Modifier::Meta            # Super/Windows

# Combine with |
mods = Input::Modifier::Ctrl | Input::Modifier::Shift

# Check modifiers
mods.ctrl?
mods.shift?
mods.alt?
mods.meta?
```

## Roadmap

**Current Status: v0.1.0 (async event system complete)**

| Component           | Status      |
| ------------------- | ----------- |
| Terminal I/O        | ✅ Complete |
| Terminfo            | ✅ Complete |
| Double Buffering    | ✅ Complete |
| Colors              | ✅ Complete |
| Termisu::Attributes | ✅ Complete |
| Keyboard Input      | ✅ Complete |
| Mouse Input         | ✅ Complete |
| Event System        | ✅ Complete |
| Async Event Loop    | ✅ Complete |
| Resize Events       | ✅ Complete |
| Timer/Tick Events   | ✅ Complete |
| Terminal Modes      | ✅ Complete |
| Synchronized Updates| ✅ Complete |
| Unicode/Wide Chars  | 🔄 Planned  |

### Completed

- **Terminal I/O** - Raw mode, alternate screen, EINTR handling
- **Terminfo** - Binary parser (16/32-bit), 414 capabilities, builtin fallbacks
- **Double Buffering** - Diff-based rendering, cell batching, state caching
- **Colors** - ANSI-8, ANSI-256, RGB/TrueColor with conversions
- **Termisu::Attributes** - Bold, underline, blink, reverse, dim, italic, hidden, strikethrough
- **Keyboard Input** - 170+ keys, F1-F24, modifiers (Ctrl/Alt/Shift/Meta)
- **Mouse Input** - SGR (mode 1006), normal (mode 1000), motion events
- **Event System** - Unified Key/Mouse events, Kitty protocol, modifyOtherKeys
- **Async Event Loop** - Crystal fiber/channel-based multiplexer
- **Resize Events** - SIGWINCH-based with debouncing
- **Timer Events** - Sleep-based and kernel-level (timerfd/kqueue) timers
- **Terminal Modes** - Cooked, cbreak, password modes with seamless TUI restoration
- **Performance** - RenderState optimization, escape sequence batching
- **Terminfo tparm** - Full processor with conditionals, stack, variables
- **Logging** - Structured async/sync dispatch, zero hot-path overhead
- **Synchronized Updates** - DEC mode 2026 (prevents screen tearing)

### Planned

- **Unicode/wide character support** - CJK, emoji (wcwidth)
- **Image protocols** - Sixel and Kitty graphics for inline images

## Inspiration

Termisu is inspired by and follows some of the design philosophy of:

- [nsf/termbox](https://github.com/nsf/termbox) - The original termbox library
- [nsf/termbox-go](https://github.com/nsf/termbox-go) - Go implementation of termbox

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for detailed guidelines.

1. Fork it (<https://github.com/omarluq/termisu/fork>)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## Contributors

- [omarluq](https://github.com/omarluq) - creator and maintainer

## License

The shard is available as open source under the terms of the [MIT License](LICENSE.txt).

## Code of conduct

Everyone interacting in this project’s codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](CODE_OF_CONDUCT.md).
