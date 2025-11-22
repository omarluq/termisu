# Terminal color support with ANSI-8, ANSI-256, and RGB/TrueColor modes.
#
# Termisu supports three color modes:
#
# ## ANSI-8 (Basic Colors)
#
# The standard 8 ANSI colors (0-7) supported by all terminals:
# Black, Red, Green, Yellow, Blue, Magenta, Cyan, White
#
# ## ANSI-256 (Extended Palette)
#
# 256-color palette with:
# - 0-7: Standard ANSI colors
# - 8-15: Bright variants
# - 16-231: 6×6×6 RGB color cube
# - 232-255: 24-step grayscale ramp
#
# ## RGB/TrueColor
#
# 24-bit true color with 16.7 million colors (requires terminal support).
#
# ## Usage
#
# ```
# # Basic ANSI colors
# red = Color.red
# blue = Color.blue
#
# # 256-color palette
# orange = Color.ansi256(208)
#
# # RGB/TrueColor
# custom = Color.rgb(255, 128, 64)
#
# # Color conversion
# ansi = custom.to_ansi256 # Convert RGB to closest 256-color
# ```
struct Termisu::Color
  # Color mode enumeration.
  enum Mode
    ANSI8   # Basic 8 colors (0-7)
    ANSI256 # Extended 256-color palette
    RGB     # 24-bit true color
  end

  # Named ANSI colors for convenience.
  enum Name
    Black
    Red
    Green
    Yellow
    Blue
    Magenta
    Cyan
    White
  end

  getter mode : Mode

  # ANSI color index (0-255) for ANSI8 and ANSI256 modes.
  getter index : Int32

  # RGB components (0-255) for RGB mode.
  getter r : UInt8
  getter g : UInt8
  getter b : UInt8

  # Special value for default terminal color.
  DEFAULT_INDEX = -1

  # Creates a color in the specified mode.
  protected def initialize(@mode : Mode, @index : Int32 = 0, @r : UInt8 = 0_u8, @g : UInt8 = 0_u8, @b : UInt8 = 0_u8)
  end

  # Creates an ANSI-8 basic color (0-7).
  def self.ansi8(index : Int32) : Color
    Validator.validate_ansi8(index)
    new(Mode::ANSI8, index: index)
  end

  # Creates an ANSI-256 palette color (0-255).
  #
  # Can be called as:
  # - `Color.ansi256(208)` - method style
  # - `Color.new_ansi256(208)` - alternative method style
  def self.ansi256(index : Int32) : Color
    Validator.validate_ansi256(index)
    new(Mode::ANSI256, index: index)
  end

  # Creates an RGB/TrueColor color.
  #
  # Can be called as:
  # - `Color.rgb(255, 128, 64)` - method style
  # - `Color.new_rgb(255, 128, 64)` - alternative method style
  def self.rgb(r : Int, g : Int, b : Int) : Color
    new(Mode::RGB, r: r.to_u8, g: g.to_u8, b: b.to_u8)
  end

  # Creates a color from a hex string (#RRGGBB or RRGGBB).
  def self.from_hex(hex : String) : Color
    hex = hex.lchop('#')
    Validator.validate_hex(hex)

    r = hex[0..1].to_u8(16)
    g = hex[2..3].to_u8(16)
    b = hex[4..5].to_u8(16)

    rgb(r, g, b)
  end

  # Returns the default terminal color.
  def self.default : Color
    ansi8(DEFAULT_INDEX)
  end

  # Named color constants (enum-style syntax).
  Black   = ansi8(0)
  Red     = ansi8(1)
  Green   = ansi8(2)
  Yellow  = ansi8(3)
  Blue    = ansi8(4)
  Magenta = ansi8(5)
  Cyan    = ansi8(6)
  White   = ansi8(7)
  Default = ansi8(DEFAULT_INDEX)

  # Named color constructors (method-style syntax).
  {% for name, index in {black: 0, red: 1, green: 2, yellow: 3, blue: 4, magenta: 5, cyan: 6, white: 7} %}
    def self.{{name.id}} : Color
      ansi8({{index}})
    end
  {% end %}

  # Bright color variants (ANSI-256 indices 8-15).
  {% for name, index in {black: 8, red: 9, green: 10, yellow: 11, blue: 12, magenta: 13, cyan: 14, white: 15} %}
    def self.bright_{{name.id}} : Color
      ansi256({{index}})
    end
  {% end %}

  # Grayscale color from the 24-step grayscale ramp (ANSI-256 indices 232-255).
  #
  # ## Parameters
  #
  # - `level`: Grayscale level from 0 (darkest) to 23 (brightest)
  def self.grayscale(level : Int32) : Color
    Validator.validate_grayscale(level)
    ansi256(232 + level)
  end

  # Converts this color to ANSI-256 palette index.
  #
  # - ANSI8 colors are mapped to their corresponding ANSI-256 indices
  # - RGB colors are converted to the nearest 256-color palette entry
  def to_ansi256 : Color
    case @mode
    when .ansi8?
      # Map ANSI-8 to ANSI-256 (same indices)
      Color.ansi256(@index)
    when .ansi256?
      self
    when .rgb?
      # Convert RGB to nearest ANSI-256 color
      index = Conversions.rgb_to_ansi256(@r, @g, @b)
      Color.ansi256(index)
    else
      self
    end
  end

  # Converts this color to ANSI-8 (basic colors only).
  #
  # - ANSI-256 colors are mapped to nearest ANSI-8 color
  # - RGB colors are converted to nearest ANSI-8 color
  def to_ansi8 : Color
    case @mode
    when .ansi8?
      self
    when .ansi256?, .rgb?
      # Convert to RGB first if needed, then to ANSI-8
      r, g, b = to_rgb_components
      index = Conversions.rgb_to_ansi8(r, g, b)
      Color.ansi8(index)
    else
      self
    end
  end

  # Returns RGB components for this color.
  #
  # Converts ANSI palette colors to their approximate RGB values.
  def to_rgb_components : {UInt8, UInt8, UInt8}
    case @mode
    when .rgb?
      {@r, @g, @b}
    when .ansi8?
      Conversions.ansi8_to_rgb(@index)
    when .ansi256?
      Conversions.ansi256_to_rgb(@index)
    else
      {0_u8, 0_u8, 0_u8}
    end
  end

  # Converts this color to RGB mode.
  def to_rgb : Color
    r, g, b = to_rgb_components
    Color.rgb(r, g, b)
  end

  # Returns whether this is the default terminal color.
  def default? : Bool
    @index == DEFAULT_INDEX
  end

  # Returns a string representation of this color.
  def to_s(io : IO)
    Formatters.to_s(self, io)
  end

  # Equality comparison.
  def ==(other : Color) : Bool
    return false if @mode != other.mode

    case @mode
    when .ansi8?, .ansi256?
      @index == other.index
    when .rgb?
      @r == other.r && @g == other.g && @b == other.b
    else
      false
    end
  end
end

# Load color modules
require "./color/*"
