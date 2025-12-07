require "../src/termisu"

# Interactive showcase demonstrating all Termisu features.
# Press 'q' to quit, any other key to see it displayed.

termisu = Termisu.new

begin
  width, height = termisu.size
  frame = 0

  # --- Draw static UI ---

  y = 0

  # Header box (centered title)
  title_text = "TERMISU SHOWCASE"
  box_inner = title_text.size + 8 # 4 spaces padding on each side
  box_width = box_inner + 2       # +2 for border chars
  box_x = [(width - box_width) // 2, 0].max
  padding = (box_inner - title_text.size) // 2

  box_top = "╔" + "═" * box_inner + "╗"
  box_mid = "║" + " " * padding + title_text + " " * padding + "║"
  box_bot = "╚" + "═" * box_inner + "╝"

  box_top.each_char_with_index do |char, idx|
    termisu.set_cell(box_x + idx, y, char, fg: Termisu::Color.cyan, attr: Termisu::Attribute::Bold)
  end
  y += 1
  box_mid.each_char_with_index do |char, idx|
    termisu.set_cell(box_x + idx, y, char, fg: Termisu::Color.cyan, attr: Termisu::Attribute::Bold)
  end
  y += 1
  box_bot.each_char_with_index do |char, idx|
    termisu.set_cell(box_x + idx, y, char, fg: Termisu::Color.cyan, attr: Termisu::Attribute::Bold)
  end
  y += 1

  subtitle = "Pure Crystal Terminal UI Library | #{width}x#{height}"
  start_x = [(width - subtitle.size) // 2, 0].max
  subtitle.each_char_with_index do |char, idx|
    termisu.set_cell(start_x + idx, y, char, fg: Termisu::Color.ansi256(245))
  end
  y += 2

  # Content width for centering sections
  content_width = 64
  margin = [(width - content_width) // 2, 0].max

  # --- ANSI-8 Colors (Basic 8) ---
  label = "ANSI-8 Colors:"
  label.each_char_with_index do |char, idx|
    termisu.set_cell(margin + idx, y, char, fg: Termisu::Color.yellow)
  end
  y += 1

  ansi8_colors = [
    {Termisu::Color.black, "Blk"},
    {Termisu::Color.red, "Red"},
    {Termisu::Color.green, "Grn"},
    {Termisu::Color.yellow, "Yel"},
    {Termisu::Color.blue, "Blu"},
    {Termisu::Color.magenta, "Mag"},
    {Termisu::Color.cyan, "Cyn"},
    {Termisu::Color.white, "Wht"},
  ]

  col_x = margin
  ansi8_colors.each do |color, name|
    termisu.set_cell(col_x, y, ' ', bg: color)
    termisu.set_cell(col_x + 1, y, ' ', bg: color)
    name.each_char_with_index do |char, idx|
      termisu.set_cell(col_x + 3 + idx, y, char, fg: color)
    end
    col_x += 8
  end
  y += 2

  # --- ANSI-256 Bright Colors (8-15) ---
  label = "Bright Colors:"
  label.each_char_with_index do |char, idx|
    termisu.set_cell(margin + idx, y, char, fg: Termisu::Color.yellow)
  end
  y += 1

  bright_colors = [
    {Termisu::Color.bright_black, "Blk"},
    {Termisu::Color.bright_red, "Red"},
    {Termisu::Color.bright_green, "Grn"},
    {Termisu::Color.bright_yellow, "Yel"},
    {Termisu::Color.bright_blue, "Blu"},
    {Termisu::Color.bright_magenta, "Mag"},
    {Termisu::Color.bright_cyan, "Cyn"},
    {Termisu::Color.bright_white, "Wht"},
  ]

  col_x = margin
  bright_colors.each do |color, name|
    termisu.set_cell(col_x, y, ' ', bg: color)
    termisu.set_cell(col_x + 1, y, ' ', bg: color)
    name.each_char_with_index do |char, idx|
      termisu.set_cell(col_x + 3 + idx, y, char, fg: color)
    end
    col_x += 8
  end
  y += 2

  # --- Text Attributes ---
  label = "Text Attributes:"
  label.each_char_with_index do |char, idx|
    termisu.set_cell(margin + idx, y, char, fg: Termisu::Color.yellow)
  end
  y += 1

  attributes = [
    {"Normal", Termisu::Attribute::None},
    {"Bold", Termisu::Attribute::Bold},
    {"Underline", Termisu::Attribute::Underline},
    {"Reverse", Termisu::Attribute::Reverse},
    {"Dim", Termisu::Attribute::Dim},
    {"Italic", Termisu::Attribute::Cursive},
    {"Blink", Termisu::Attribute::Blink},
  ]

  col_x = margin
  attributes.each do |name, attr|
    name.each_char_with_index do |char, idx|
      termisu.set_cell(col_x + idx, y, char, fg: Termisu::Color.white, attr: attr)
    end
    col_x += name.size + 2
  end
  y += 2

  # Combined attributes
  label = "Combined: "
  label.each_char_with_index do |char, idx|
    termisu.set_cell(margin + idx, y, char, fg: Termisu::Color.yellow)
  end
  col_x = margin + label.size

  combined = "Bold+Underline"
  combined.each_char_with_index do |char, idx|
    termisu.set_cell(col_x + idx, y, char, fg: Termisu::Color.green,
      attr: Termisu::Attribute::Bold | Termisu::Attribute::Underline)
  end
  col_x += combined.size + 3

  combined = "Dim+Italic"
  combined.each_char_with_index do |char, idx|
    termisu.set_cell(col_x + idx, y, char, fg: Termisu::Color.cyan,
      attr: Termisu::Attribute::Dim | Termisu::Attribute::Cursive)
  end
  y += 2

  # --- ANSI-256 Palette ---
  label = "ANSI-256 Palette:"
  label.each_char_with_index do |char, idx|
    termisu.set_cell(margin + idx, y, char, fg: Termisu::Color.yellow)
  end
  y += 1

  # Standard 16 colors
  16.times do |idx|
    termisu.set_cell(margin + idx * 2, y, ' ', bg: Termisu::Color.ansi256(idx))
    termisu.set_cell(margin + idx * 2 + 1, y, ' ', bg: Termisu::Color.ansi256(idx))
  end
  y += 1

  # 6x6x6 cube (show 2 rows)
  36.times do |col|
    termisu.set_cell(margin + col, y, ' ', bg: Termisu::Color.ansi256(16 + col))
  end
  y += 1
  36.times do |col|
    termisu.set_cell(margin + col, y, ' ', bg: Termisu::Color.ansi256(16 + 36 + col))
  end
  y += 1

  # Grayscale (using dedicated grayscale method)
  24.times do |level|
    color = Termisu::Color.grayscale(level)
    termisu.set_cell(margin + level * 2, y, '█', fg: color)
    termisu.set_cell(margin + level * 2 + 1, y, '█', fg: color)
  end
  y += 2

  # --- RGB Gradient (6 rows - full HSV spectrum) ---
  label = "RGB TrueColor (16.7M colors):"
  label.each_char_with_index do |char, idx|
    termisu.set_cell(margin + idx, y, char, fg: Termisu::Color.yellow)
  end
  y += 1

  # Full HSV color space: hue across columns, brightness down rows
  gradient_width = [64, width - margin * 2].min
  6.times do |row|
    brightness = 1.0 - (row * 0.15) # 100% down to 25%
    gradient_width.times do |idx|
      # HSV to RGB conversion (saturation=1, varying brightness)
      hue = (idx.to_f / gradient_width) * 360
      h_section = (hue / 60).to_i % 6
      f = (hue / 60) - h_section
      v = (255 * brightness).to_i
      p = 0
      q = (v * (1 - f)).to_i
      t = (v * f).to_i

      r, g, b = case h_section
                when 0 then {v, t, p}
                when 1 then {q, v, p}
                when 2 then {p, v, t}
                when 3 then {p, q, v}
                when 4 then {t, p, v}
                else        {v, p, q}
                end

      termisu.set_cell(margin + idx, y + row, '█', fg: Termisu::Color.rgb(r, g, b))
    end
  end
  y += 7

  # --- Color Conversions (from colors.cr) ---
  label = "Color Conversion: RGB→ANSI256→ANSI8"
  label.each_char_with_index do |char, idx|
    termisu.set_cell(margin + idx, y, char, fg: Termisu::Color.yellow)
  end
  y += 1

  rgb_color = Termisu::Color.rgb(255, 128, 64)
  ansi256_color = rgb_color.to_ansi256
  ansi8_color = rgb_color.to_ansi8

  # Original RGB
  "RGB:".each_char_with_index { |char, idx| termisu.set_cell(margin + idx, y, char, fg: Termisu::Color.white) }
  6.times { |idx| termisu.set_cell(margin + 5 + idx, y, '█', fg: rgb_color) }

  # ANSI-256
  "256:".each_char_with_index { |char, idx| termisu.set_cell(margin + 14 + idx, y, char, fg: Termisu::Color.white) }
  6.times { |idx| termisu.set_cell(margin + 19 + idx, y, '█', fg: ansi256_color) }

  # ANSI-8
  "8:".each_char_with_index { |char, idx| termisu.set_cell(margin + 28 + idx, y, char, fg: Termisu::Color.white) }
  6.times { |idx| termisu.set_cell(margin + 31 + idx, y, '█', fg: ansi8_color) }
  y += 2

  # --- Hex Colors (from colors.cr) ---
  label = "Hex Colors:"
  label.each_char_with_index do |char, idx|
    termisu.set_cell(margin + idx, y, char, fg: Termisu::Color.yellow)
  end
  y += 1

  hex_colors = ["#FF0000", "#00FF00", "#0000FF", "#FFFF00", "#FF00FF", "#00FFFF"]
  hex_colors.each_with_index do |hex, idx|
    color = Termisu::Color.from_hex(hex)
    4.times { |index| termisu.set_cell(margin + idx * 10 + index, y, '█', fg: color) }
    hex.each_char_with_index do |char, char_idx|
      termisu.set_cell(margin + idx * 10 + char_idx, y + 1, char, fg: Termisu::Color.ansi256(245))
    end
  end
  y += 3

  # --- Background Colors ---
  label = "Background Colors:"
  label.each_char_with_index do |char, idx|
    termisu.set_cell(margin + idx, y, char, fg: Termisu::Color.yellow)
  end
  y += 1

  text = "Text on colored backgrounds"
  text.each_char_with_index do |char, col|
    bg_color = Termisu::Color.ansi256(16 + (col * 7) % 216)
    termisu.set_cell(margin + col, y, char, fg: Termisu::Color.white, bg: bg_color)
  end
  y += 2

  # --- Interactive Section ---
  status_y = y
  key_y = y + 1
  hint_y = height - 1

  hint = "Press 'q' to quit | Press any key to see it displayed"
  hint_x = [(width - hint.size) // 2, 0].max
  hint.each_char_with_index do |char, idx|
    termisu.set_cell(hint_x + idx, hint_y, char, fg: Termisu::Color.ansi256(245))
  end

  # Initial render
  termisu.render

  # --- Main Loop ---
  spinners = ['⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏']

  loop do
    # Wait for input with 100ms timeout for animation
    if termisu.wait_for_input(100)
      if byte = termisu.read_byte
        # Quit on 'q'
        break if byte == 'q'.ord || byte == 'Q'.ord

        # Display pressed key
        50.times { |col| termisu.set_cell(margin + col, key_y, ' ') } # Clear line

        key_char = byte.chr
        display = key_char.printable? ? "'#{key_char}'" : "(non-printable)"
        msg = "Key: #{display}  byte=#{byte}  hex=0x#{byte.to_s(16).upcase.rjust(2, '0')}"
        msg.each_char_with_index do |char, col|
          termisu.set_cell(margin + col, key_y, char, fg: Termisu::Color.magenta, attr: Termisu::Attribute::Bold)
        end
      end
    end

    # Update animation
    frame += 1
    spinner = spinners[frame % spinners.size]

    # Clear and redraw status line
    60.times { |col| termisu.set_cell(margin + col, status_y, ' ') }

    status = "#{spinner} Running... Frame #{frame}"
    status.each_char_with_index do |char, col|
      termisu.set_cell(margin + col, status_y, char, fg: Termisu::Color.green)
    end

    # Color cycling dots
    3.times do |dot|
      color_idx = ((frame * 3) + (dot * 72)) % 216 + 16
      termisu.set_cell(width - 4 + dot, status_y, '●', fg: Termisu::Color.ansi256(color_idx))
    end

    termisu.render
  end

  # Animated goodbye (from demo.cr)
  60.times { |col| termisu.set_cell(margin + col, status_y, ' ') }
  60.times { |col| termisu.set_cell(margin + col, key_y, ' ') }

  goodbye = "Thanks for trying Termisu! Goodbye! 👋"
  termisu.set_cursor(margin, status_y)
  termisu.render
  sleep 0.2.seconds

  goodbye.each_char_with_index do |char, idx|
    termisu.set_cell(margin + idx, status_y, char, fg: Termisu::Color.cyan, attr: Termisu::Attribute::Bold)
    termisu.set_cursor(margin + idx + 1, status_y)
    termisu.render
    sleep 0.03.seconds
  end

  # Blink cursor a few times
  3.times do
    termisu.hide_cursor
    termisu.render
    sleep 0.15.seconds
    termisu.set_cursor(margin + goodbye.size, status_y)
    termisu.render
    sleep 0.15.seconds
  end

  termisu.hide_cursor
  termisu.render
  sleep 0.5.seconds
ensure
  termisu.close
end
