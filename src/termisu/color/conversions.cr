# Color conversion algorithms.
#
# Provides conversion between ANSI-8, ANSI-256, and RGB color modes.
# All conversion methods are stateless and side-effect free.
module Termisu::Color::Conversions
  extend self

  # ANSI-256 color cube structure
  CUBE_LEVELS     = [0_u8, 95_u8, 135_u8, 175_u8, 215_u8, 255_u8]
  CUBE_THRESHOLDS = [48_u8, 115_u8, 155_u8, 195_u8, 235_u8]

  # ANSI-8 standard color palette (RGB values)
  ANSI8_PALETTE = {
    0 => {0_u8, 0_u8, 0_u8},       # Black
    1 => {170_u8, 0_u8, 0_u8},     # Red
    2 => {0_u8, 170_u8, 0_u8},     # Green
    3 => {170_u8, 85_u8, 0_u8},    # Yellow
    4 => {0_u8, 0_u8, 170_u8},     # Blue
    5 => {170_u8, 0_u8, 170_u8},   # Magenta
    6 => {0_u8, 170_u8, 170_u8},   # Cyan
    7 => {170_u8, 170_u8, 170_u8}, # White
  }

  # Brightness boost for bright colors (indices 8-15)
  BRIGHT_BOOST = 85_u8

  # Grayscale ramp constants
  GRAYSCALE_START  =  232
  GRAYSCALE_END    =  255
  GRAYSCALE_OFFSET = 8_u8
  GRAYSCALE_STEP   =   10

  # RGB to ANSI-256 conversion thresholds
  GRAYSCALE_MIN_THRESHOLD =   8_u8
  GRAYSCALE_MAX_THRESHOLD = 247_u8

  # Converts RGB to nearest ANSI-256 palette color.
  def rgb_to_ansi256(r : UInt8, g : UInt8, b : UInt8) : Int32
    # Check if it's a grayscale color
    if r == g && g == b
      return rgb_to_grayscale_index(r)
    end

    # 6×6×6 color cube (16-231)
    r_index = rgb_to_cube_index(r)
    g_index = rgb_to_cube_index(g)
    b_index = rgb_to_cube_index(b)

    16 + (r_index * 36) + (g_index * 6) + b_index
  end

  # Converts RGB to nearest ANSI-8 color using threshold-based mapping.
  def rgb_to_ansi8(r : UInt8, g : UInt8, b : UInt8) : Int32
    threshold = 128_u8

    index = 0
    index |= 1 if r >= threshold # Red bit
    index |= 2 if g >= threshold # Green bit
    index |= 4 if b >= threshold # Blue bit

    index
  end

  # Converts ANSI-8 color index to RGB components.
  def ansi8_to_rgb(index : Int32) : {UInt8, UInt8, UInt8}
    return {0_u8, 0_u8, 0_u8} if index == -1 # Default color

    ANSI8_PALETTE.fetch(index) { {0_u8, 0_u8, 0_u8} }
  end

  # Converts ANSI-256 color index to RGB components.
  def ansi256_to_rgb(index : Int32) : {UInt8, UInt8, UInt8}
    return {0_u8, 0_u8, 0_u8} if index == -1 # Default color

    case index
    when 0..7
      ansi8_to_rgb(index)
    when 8..15
      bright_color_to_rgb(index)
    when 16..231
      cube_color_to_rgb(index)
    when GRAYSCALE_START..GRAYSCALE_END
      grayscale_to_rgb(index)
    else
      {0_u8, 0_u8, 0_u8}
    end
  end

  # Private helper: Converts RGB component to 6-level cube index (0-5).
  private def rgb_to_cube_index(component : UInt8) : Int32
    CUBE_THRESHOLDS.each_with_index do |threshold, idx|
      return idx if component < threshold
    end
    5
  end

  # Private helper: Converts RGB grayscale to ANSI-256 grayscale index.
  private def rgb_to_grayscale_index(gray : UInt8) : Int32
    return GRAYSCALE_START if gray < GRAYSCALE_MIN_THRESHOLD
    return GRAYSCALE_END if gray > GRAYSCALE_MAX_THRESHOLD

    gray_level = ((gray - GRAYSCALE_OFFSET) / GRAYSCALE_STEP).to_i
    GRAYSCALE_START + gray_level
  end

  # Private helper: Converts bright ANSI-256 color (8-15) to RGB.
  private def bright_color_to_rgb(index : Int32) : {UInt8, UInt8, UInt8}
    r, g, b = ansi8_to_rgb(index - 8)
    {(r + BRIGHT_BOOST).to_u8, (g + BRIGHT_BOOST).to_u8, (b + BRIGHT_BOOST).to_u8}
  end

  # Private helper: Converts 6×6×6 color cube index to RGB.
  private def cube_color_to_rgb(index : Int32) : {UInt8, UInt8, UInt8}
    cube_index = index - 16
    r_index = (cube_index / 36).to_i
    g_index = ((cube_index % 36) / 6).to_i
    b_index = (cube_index % 6).to_i

    r = CUBE_LEVELS[r_index]
    g = CUBE_LEVELS[g_index]
    b = CUBE_LEVELS[b_index]

    {r, g, b}
  end

  # Private helper: Converts grayscale index (232-255) to RGB.
  private def grayscale_to_rgb(index : Int32) : {UInt8, UInt8, UInt8}
    gray = GRAYSCALE_OFFSET + ((index - GRAYSCALE_START) * GRAYSCALE_STEP).to_u8
    {gray, gray, gray}
  end
end
