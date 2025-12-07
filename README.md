[![Crystal Version](https://img.shields.io/badge/crystal-%3E%3D1.18.2-000000.svg?style=flat-square)](https://crystal-lang.org/)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg?style=flat-square)](LICENSE)
![Cooking](https://img.shields.io/badge/🍳-cooking-orange?style=flat-square)

# Termisu

<img src="assets/termisu.png" align="right" alt="Termisu Logo" width="250"/>

Termisu is a library that provides a minimalistic API for writing text-based user interfaces in pure Crystal. It offers an abstraction layer over terminal capabilities through cell-based rendering with double buffering, allowing efficient and flicker-free TUI development. The API is intentionally small and focused, making it easy to learn, test, and maintain. Inspired by termbox, Termisu brings similar simplicity and elegance to the Crystal ecosystem.

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
  # Set individual cells with colors and attributes
  termisu.set_cell(0, 0, 'H', fg: Termisu::Color.red, attr: Termisu::Attribute::Bold)
  termisu.set_cell(1, 0, 'i', fg: Termisu::Color.green)

  # Position and show cursor
  termisu.set_cursor(3, 0)

  # Render only changed cells (diff-based)
  termisu.render

  # Wait for input
  if termisu.wait_for_input(5000)
    byte = termisu.read_byte
  end
ensure
  termisu.close
end
```

See `examples/showcase.cr` for a complete demonstration.

![Termisu Showcase](assets/demo-screenshot.png)

## Roadmap

**Current Status: Alpha**

### Completed

- Terminal I/O primitives (raw mode, alternate screen)
- Terminfo database parser with builtin fallbacks
- Cell-based rendering with double buffering
- Full color support (ANSI-8, ANSI-256, RGB/TrueColor)
- Color conversions between all modes
- Text attributes (bold, underline, blink, reverse, dim, italic, hidden)
- Cursor control (position, visibility)
- Input reading (bytes, with timeout)
- Modular color architecture
- Performance optimizations (RenderState batching, cursor tracking)
- tparm() processor for parametrized terminfo capabilities

### In Progress

- Mouse input handling
- Event system (keyboard, mouse, resize)

### Planned

- Higher-level widgets and layout system (Maybe)

## Inspiration

Termisu is inspired by and follows the design philosophy of:

- [nsf/termbox](https://github.com/nsf/termbox) - The original termbox library
- [nsf/termbox-go](https://github.com/nsf/termbox-go) - Go implementation of termbox

## Contributing

1. Fork it (<https://github.com/omarluq/termisu/fork>)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## Contributors

- [omarluq](https://github.com/omarluq) - creator and maintainer

## License

The gem is available as open source under the terms of the [MIT License](LICENSE.txt).

## Code of conduct

Everyone interacting in this project’s codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](CODE_OF_CONDUCT.md).
