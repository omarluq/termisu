require "../src/termisu"

# Comprehensive color example demonstrating ANSI-8, ANSI-256, and RGB/TrueColor support
termisu = Termisu.new

begin
  y = 0

  # ANSI-8: Basic 8 colors
  title = "ANSI-8 Colors (Basic):"
  title.each_char_with_index do |char, col|
    termisu.set_cell(col, y, char, fg: Termisu::Color.white)
  end
  y += 1

  colors = [
    Termisu::Color.black,
    Termisu::Color.red,
    Termisu::Color.green,
    Termisu::Color.yellow,
    Termisu::Color.blue,
    Termisu::Color.magenta,
    Termisu::Color.cyan,
    Termisu::Color.white,
  ]

  colors.each_with_index do |color, idx|
    termisu.set_cell(idx * 3, y, '█', fg: color)
    termisu.set_cell(idx * 3 + 1, y, '█', fg: color)
  end
  y += 2

  # ANSI-256: Bright colors (8-15)
  title = "ANSI-256 Bright Colors:"
  title.each_char_with_index do |char, col|
    termisu.set_cell(col, y, char, fg: Termisu::Color.white)
  end
  y += 1

  bright_colors = [
    Termisu::Color.bright_black,
    Termisu::Color.bright_red,
    Termisu::Color.bright_green,
    Termisu::Color.bright_yellow,
    Termisu::Color.bright_blue,
    Termisu::Color.bright_magenta,
    Termisu::Color.bright_cyan,
    Termisu::Color.bright_white,
  ]

  bright_colors.each_with_index do |color, idx|
    termisu.set_cell(idx * 3, y, '█', fg: color)
    termisu.set_cell(idx * 3 + 1, y, '█', fg: color)
  end
  y += 2

  # ANSI-256: 6×6×6 color cube (16-231)
  title = "ANSI-256 Color Cube (216 colors):"
  title.each_char_with_index do |char, col|
    termisu.set_cell(col, y, char, fg: Termisu::Color.white)
  end
  y += 1

  # Show a subset of the cube (every 6th color for compact display)
  36.times do |index|
    color_idx = 16 + (index * 6)
    color = Termisu::Color.ansi256(color_idx)
    termisu.set_cell(index * 2, y, '█', fg: color)
    termisu.set_cell(index * 2 + 1, y, '█', fg: color)
  end
  y += 2

  # ANSI-256: Grayscale ramp (232-255)
  title = "ANSI-256 Grayscale (24 levels):"
  title.each_char_with_index do |char, col|
    termisu.set_cell(col, y, char, fg: Termisu::Color.white)
  end
  y += 1

  24.times do |level|
    color = Termisu::Color.grayscale(level)
    termisu.set_cell(level * 3, y, '█', fg: color)
    termisu.set_cell(level * 3 + 1, y, '█', fg: color)
  end
  y += 2

  # RGB/TrueColor: Custom colors
  title = "RGB/TrueColor (16.7M colors):"
  title.each_char_with_index do |char, col|
    termisu.set_cell(col, y, char, fg: Termisu::Color.white)
  end
  y += 1

  # Rainbow gradient
  60.times do |index|
    hue = (index * 6).to_f
    r = ((Math.sin(hue * Math::PI / 180) * 127) + 128).to_i
    g = ((Math.sin((hue + 120) * Math::PI / 180) * 127) + 128).to_i
    b = ((Math.sin((hue + 240) * Math::PI / 180) * 127) + 128).to_i
    color = Termisu::Color.rgb(r, g, b)
    termisu.set_cell(index, y, '█', fg: color)
  end
  y += 2

  # Color conversions
  title = "Color Conversions:"
  title.each_char_with_index do |char, col|
    termisu.set_cell(col, y, char, fg: Termisu::Color.white)
  end
  y += 1

  rgb_color = Termisu::Color.rgb(255, 128, 64)
  msg = "RGB(255,128,64) -> ANSI-256 -> ANSI-8"
  msg.each_char_with_index do |char, col|
    termisu.set_cell(col, y, char, fg: Termisu::Color.white)
  end
  y += 1

  # Original RGB
  8.times do |index|
    termisu.set_cell(index, y, '█', fg: rgb_color)
  end

  # Convert to ANSI-256
  ansi256_color = rgb_color.to_ansi256
  8.times do |index|
    termisu.set_cell(index + 10, y, '█', fg: ansi256_color)
  end

  # Convert to ANSI-8
  ansi8_color = rgb_color.to_ansi8
  8.times do |index|
    termisu.set_cell(index + 20, y, '█', fg: ansi8_color)
  end
  y += 2

  # Hex color parsing
  title = "Hex Colors:"
  title.each_char_with_index do |char, col|
    termisu.set_cell(col, y, char, fg: Termisu::Color.white)
  end
  y += 1

  hex_colors = ["#FF0000", "#00FF00", "#0000FF", "#FFFF00", "#FF00FF", "#00FFFF"]
  hex_colors.each_with_index do |hex, idx|
    color = Termisu::Color.from_hex(hex)
    4.times do |index|
      termisu.set_cell(idx * 8 + index, y, '█', fg: color)
    end
    hex.each_char_with_index do |char, char_idx|
      termisu.set_cell(idx * 8 + char_idx, y + 1, char, fg: Termisu::Color.white)
    end
  end
  y += 3

  # Background colors
  title = "Background Colors:"
  title.each_char_with_index do |char, col|
    termisu.set_cell(col, y, char, fg: Termisu::Color.white)
  end
  y += 1

  msg = "Text with backgrounds"
  msg.each_char_with_index do |char, col|
    bg = Termisu::Color.ansi256(16 + (col * 8))
    termisu.set_cell(col, y, char, fg: Termisu::Color.white, bg: bg)
  end

  # Position cursor and render
  termisu.set_cursor(0, y + 2)
  termisu.render
end
