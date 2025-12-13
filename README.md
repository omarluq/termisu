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
  termisu.set_cell(0, 0, 'H', fg: Termisu::Color.red, attr: Termisu::Termisu::Attribute::Bold)
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
  when Termisu::Event::Key    then # keyboard
  when Termisu::Event::Mouse  then # mouse click/move
  when Termisu::Event::Resize then # terminal resized
  when Termisu::Event::Tick   then # timer tick (if enabled)
  end
end
```

### Event Types

`Event::Any` is the union type: `Event::Key | Event::Mouse | Event::Resize | Event::Tick`

```crystal
# Event::Key - Keyboard input
event.key                          # => Input::Key
event.char                         # => Char?
event.modifiers                    # => Input::Modifier
event.ctrl? / event.alt? / event.shift? / event.meta?

# Event::Mouse - Mouse input
event.x, event.y                   # Position (1-based)
event.button                       # => MouseButton
event.motion?                      # Mouse moved while button held
event.press?                       # Button press (not release/motion)
event.wheel?                       # Scroll wheel event
event.ctrl? / event.alt? / event.shift?

# MouseButton enum
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
termisu.enable_timer(16.milliseconds)    # ~60 FPS tick events
termisu.disable_timer
termisu.timer_enabled?
termisu.timer_interval = 8.milliseconds  # Change interval
```

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
- **Timer Events** - Configurable tick interval for animations
- **Performance** - RenderState optimization, escape sequence batching
- **Terminfo tparm** - Full processor with conditionals, stack, variables
- **Logging** - Structured async/sync dispatch, zero hot-path overhead

### Planned

- **Unicode/wide character support** - CJK, emoji (wcwidth)
- **Synchronized updates** - DEC mode 2026 (prevents screen tearing)
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
