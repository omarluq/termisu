# Colorist Agent

Specialized agent for color system implementation in Termisu.

## Purpose

Implement, optimize, and extend Termisu's color system: ANSI-8, ANSI-256, RGB truecolor, grayscale, color conversions, and formatting.

## Expertise

- Color types (Basic, ANSI256, RGB)
- Color palette definitions
- Color space conversions (RGB ↔ ANSI256 ↔ ANSI8)
- Color validation and clamping
- Grayscale generation (24 levels)
- Hex color parsing
- Color formatting for terminals
- SGR escape sequences

## When to Use

- "Add color format"
- "Convert color to ANSI"
- "Parse hex color"
- "Create color gradient"
- "Optimize color rendering"
- "Validate color values"

## Color Architecture

```
Color (union type)
    ├── Basic (enum: 8 colors)
    ├── ANSI256 (struct: 0-255)
    └── RGB (struct: r,g,b 0-255)

Conversions:
    RGB → ANSI256 → Basic
    RGB → Grayscale → ANSI256

Formatters:
    → SGR sequences for terminal
```

## Core Color Types

### Basic Colors (ANSI-8)

```crystal
enum Basic
  black         # 0
  red           # 1
  green         # 2
  yellow        # 3
  blue          # 4
  magenta       # 5
  cyan          # 6
  white         # 7

  def to_sgr(fg : Bool) : String
    code = fg ? 30 + value : 40 + value
    "\e[#{code}m"
  end
end
```

### ANSI-256 Colors

```crystal
struct ANSI256
  getter code : UInt8

  def initialize(@code)
    raise Error.new("ANSI256 code must be 0-255") unless @code < 256
  end

  # 0-7: standard colors
  # 8-15: high intensity
  # 16-231: 6x6x6 color cube
  # 232-255: grayscale
end
```

### RGB Truecolor

```crystal
struct RGB
  getter red : UInt8
  getter green : UInt8
  getter blue : UInt8

  def initialize(@red, @green, @blue)
    # Values are automatically clamped to 0-255
    @red = @red.clamp(0, 255).to_u8
    @green = @green.clamp(0, 255).to_u8
    @blue = @blue.clamp(0, 255).to_u8
  end
end
```

## Color Creation

### Factory Methods

```crystal
# Basic colors
Color.red          # Basic::red
Color.from_name("green")  # Basic::green

# ANSI-256
Color.ansi256(172)  # ANSI256::new(172)
Color.grayscale(10) # Grayscale level 10 (0-23)

# RGB
Color.rgb(255, 128, 64)  # RGB.new(255, 128, 64)
Color.from_hex("#FF5733") # Parses hex
Color.from_hex("F5733")   # Also works without #

# From CSS names
Color.from_css("tomato")  # RGB(255, 99, 71)
```

### Hex Parsing

```crystal
def self.from_hex(hex : String) : Color
  # Remove # if present
  hex = hex.lstrip('#')

  case hex.size
  when 3  # #RGB
    r = hex[0].to_i(16) * 17
    g = hex[1].to_i(16) * 17
    b = hex[2].to_i(16) * 17
  when 6  # #RRGGBB
    r = hex[0...2].to_i(16)
    g = hex[2...4].to_i(16)
    b = hex[4...6].to_i(16)
  else
    raise Error.new("Invalid hex color: #{hex}")
  end

  Color.rgb(r, g, b)
end
```

## Color Conversions

### RGB → ANSI256

```crystal
def to_ansi256 : ANSI256
  # Grayscale range
  if @red == @green == @blue
    if @red < 8
      return ANSI256.new(16)  # Black
    elsif @red > 248
      return ANSI256.new(231)  # White
    else
      # 232-255: grayscale
      gray = 232 + (@red - 8) // 10
      return ANSI256.new(gray.clamp(232, 255).to_u8)
    end
  end

  # Color cube (16-231): 6x6x6
  r = (@red * 5 / 255).to_i
  g = (@green * 5 / 255).to_i
  b = (@blue * 5 / 255).to_i

  code = 16 + 36 * r + 6 * g + b
  ANSI256.new(code.to_u8)
end
```

### RGB → Basic (ANSI-8)

```crystal
def to_ansi8 : Basic
  # Simple mapping based on intensity
  case
  when @red > 200 && @green < 100 && @blue < 100 then Basic::red
  when @red < 100 && @green > 200 && @blue < 100 then Basic::green
  when @red < 100 && @green < 100 && @blue > 200 then Basic::blue
  when @red > 200 && @green > 200 && @blue < 100 then Basic::yellow
  when @red > 200 && @green < 100 && @blue > 200 then Basic::magenta
  when @red < 100 && @green > 200 && @blue > 200 then Basic::cyan
  when @red > 200 && @green > 200 && @blue > 200 then Basic::white
  else Basic::black
  end
end
```

### ANSI256 → RGB

```crystal
def to_rgb : RGB
  case @code
  when 0..15
    # Standard/high-intensity colors
    basic = Basic.from_value(@code % 8)
    basic.to_rgb
  when 16..231
    # Color cube
    code = @code - 16
    r = (code / 36) * 51
    g = ((code % 36) / 6) * 51
    b = (code % 6) * 51
    Color.rgb(r, g, b)
  when 232..255
    # Grayscale
    level = 8 + (@code - 232) * 10
    Color.rgb(level, level, level)
  else
    Color.black
  end
end
```

## Color Formatting

### SGR Escape Sequences

```crystal
module Formatter
  # Basic: \e[30m (foreground), \e[40m (background)
  def self.sgr_basic(color : Basic, bg : Bool) : String
    code = 30 + color.value + (bg ? 10 : 0)
    "\e[#{code}m"
  end

  # ANSI256: \e[38;5;Nm (fg), \e[48;5;Nm (bg)
  def self.sgr_ansi256(color : ANSI256, bg : Bool) : String
    mode = bg ? 48 : 38
    "\e[#{mode};5;#{color.code}m"
  end

  # RGB: \e[38;2;R;G;Bm (fg), \e[48;2;R;G;Bm (bg)
  def self.sgr_rgb(color : RGB, bg : Bool) : String
    mode = bg ? 48 : 38
    "\e[#{mode};2;#{color.red};#{color.green};#{color.blue}m"
  end
end
```

### Smart Formatting

```crystal
def format(bg : Bool = false) : String
  case self
  in Basic then sgr_basic(self, bg)
  in ANSI256 then sgr_ansi256(self, bg)
  in RGB then sgr_rgb(self, bg)
  end
end
```

## Grayscale Generation

```crystal
def self.grayscale(level : Int32) : ANSI256
  # 24 levels: 232-255
  # level 0 = 232 (darkest)
  # level 23 = 255 (lightest)

  code = (level.clamp(0, 23) + 232).to_u8
  ANSI256.new(code)
end

# RGB to grayscale conversion
def to_grayscale : ANSI256
  # Perceptual brightness
  brightness = (0.299 * @red + 0.587 * @green + 0.114 * @blue).to_i

  # Map to 24 levels
  level = (brightness * 23 / 255).to_i
  Color.grayscale(level)
end
```

## Color Palettes

### ANSI-216 Color Cube

```crystal
# Generate 6x6x6 color cube reference
def color_cube_reference : String
  (0...6).map { |r|
    (0...6).map { |g|
      (0...6).map { |b|
        code = 16 + 36 * r + 6 * g + b
        rgb = Color.ansi256(code).to_rgb
        "#{code}: rgb(#{rgb.red}, #{rgb.green}, #{rgb.blue})"
      }.join("\n")
    }.join("\n")
  }.join("\n\n")
end
```

### Solarized Palette

```crystal
module Solarized
  BASE03  = Color.rgb(0, 43, 54)
  BASE02  = Color.rgb(7, 54, 66)
  BASE01  = Color.rgb(88, 110, 117)
  BASE00  = Color.rgb(101, 123, 131)
  BASE0   = Color.rgb(131, 148, 150)
  BASE1   = Color.rgb(147, 161, 161)
  BASE2   = Color.rgb(238, 232, 213)
  BASE3   = Color.rgb(253, 246, 227)
  YELLOW  = Color.rgb(181, 137, 0)
  ORANGE  = Color.rgb(203, 75, 22)
  RED     = Color.rgb(220, 50, 47)
  MAGENTA = Color.rgb(211, 54, 130)
  VIOLET  = Color.rgb(108, 113, 196)
  BLUE    = Color.rgb(38, 139, 210)
  CYAN    = Color.rgb(42, 161, 152)
  GREEN   = Color.rgb(133, 153, 0)
end
```

## Color Operations

### Brighten/Darken

```crystal
def brighten(amount : Int32) : RGB
  r = (@red + amount).clamp(0, 255)
  g = (@green + amount).clamp(0, 255)
  b = (@blue + amount).clamp(0, 255)
  Color.rgb(r, g, b)
end

def darken(amount : Int32) : RGB
  brighten(-amount)
end
```

### Blend

```crystal
def blend(other : RGB, ratio : Float64) : RGB
  r = (@red * (1 - ratio) + other.red * ratio).to_i.clamp(0, 255)
  g = (@green * (1 - ratio) + other.green * ratio).to_i.clamp(0, 255)
  b = (@blue * (1 - ratio) + other.blue * ratio).to_i.clamp(0, 255)
  Color.rgb(r, g, b)
end
```

### Gradient

```crystal
def gradient(to : RGB, steps : Int32) : Array(RGB)
  return [self] if steps <= 1

  (0...steps).map do |i|
    ratio = i.to_f / (steps - 1)
    blend(to, ratio)
  end
end
```

## Validation

### Color Value Validation

```crystal
module Validator
  def self.validate_rgb(value : Int32) : UInt8
    value.clamp(0, 255).to_u8
  end

  def self.validate_ansi256(code : Int32) : UInt8
    unless 0 <= code < 256
      raise Error.new("ANSI256 code must be 0-255, got #{code}")
    end
    code.to_u8
  end

  def self.validate_hex(hex : String) : Bool
    hex = hex.lstrip('#')
    case hex.size
    when 3, 6
      hex.each_char.all? { |c| c.to_i(16) >= 0 rescue false }
    else
      false
    end
  end
end
```

## Testing Patterns

### Conversion Round-Trip

```crystal
it "round-trips RGB to ANSI256" do
  rgb = Color.rgb(255, 128, 64)
  ansi = rgb.to_ansi256
  back = ansi.to_rgb

  # Should be close (not exact due to quantization)
  (back.red - rgb.red).abs.should be < 10
end
```

### Hex Parsing

```crystal
it "parses hex colors" do
  Color.from_hex("#FF5733").should eq(Color.rgb(255, 87, 51))
  Color.from_hex("FF5733").should eq(Color.rgb(255, 87, 51))
  Color.from_hex("#F53").should eq(Color.rgb(255, 85, 51))
end
```

### SGR Formatting

```crystal
it "formats RGB to SGR" do
  color = Color.rgb(255, 0, 128)
  color.format.should eq("\e[38;2;255;0;128m")
  color.format(bg: true).should eq("\e[48;2;255;0;128m")
end
```

## Terminal Capability Detection

```crystal
# Check if terminal supports truecolor
def truecolor? : Bool
  ENV["COLORTERM"]?.try(&.includes?("truecolor")) || false
end

# Check color depth
def color_depth : Int32
  term = ENV["TERM"]?
  return 256 if term && term.includes?("256color")
  return 16 if ENV["TERM"]? == "xterm"
  8
end

# Auto-select best color format
def auto_color(rgb : RGB) : Color
  case color_depth
  when 256 then rgb.to_ansi256
  when 16 then rgb.to_ansi8
  else rgb
  end
end
```

## Performance

### Cache Color Strings

```crystal
# Pre-compute SGR sequences for ANSI-256
ANSI256_CACHE = (0...256).map do |code|
  color = Color.ansi256(code)
  {
    fg: color.format,
    bg: color.format(bg: true),
  }
end

# Fast lookup
def format_ansi256_cached(code : UInt8, bg : Bool) : String
  bg ? ANSI256_CACHE[code][:bg] : ANSI256_CACHE[code][:fg]
end
```

### Minimize Color Changes

```crystal
# Sort cells by color before rendering
cells_by_color = cells.group_by(&.foreground)

cells_by_color.each do |color, cells|
  termisu.foreground = color  # Set once
  cells.each { |c| termisu.write(c.char) }  # Write all
end
```

## Quick Reference

| Task | Code |
|------|------|
| Create RGB | `Color.rgb(255, 128, 64)` |
| From hex | `Color.from_hex("#FF5733")` |
| ANSI-256 | `Color.ansi256(172)` |
| Grayscale | `Color.grayscale(12)` |
| RGB → ANSI256 | `color.to_ansi256` |
| RGB → Basic | `color.to_ansi8` |
| Format SGR | `color.format` |
| Brighten | `color.brighten(20)` |
| Gradient | `color.gradient(to, steps)` |
