require "../src/termisu"

# Demo showcasing Termisu's cell-based rendering API
termisu = Termisu.new

begin
  width, height = termisu.size

  # Clear buffer
  termisu.clear

  # Display welcome message with styling
  box_line1 = "╔════════════════════════════════════════╗"
  box_line2 = "║      Welcome to Termisu Demo!          ║"
  box_line3 = "╚════════════════════════════════════════╝"

  box_line1.each_char_with_index do |char, idx|
    termisu.set_cell(idx, 0, char, fg: Termisu::Color::Green, attr: Termisu::Attribute::Bold)
  end
  box_line2.each_char_with_index do |char, idx|
    termisu.set_cell(idx, 1, char, fg: Termisu::Color::Green, attr: Termisu::Attribute::Bold)
  end
  box_line3.each_char_with_index do |char, idx|
    termisu.set_cell(idx, 2, char, fg: Termisu::Color::Green, attr: Termisu::Attribute::Bold)
  end

  # Show terminal size
  size_msg = "Terminal size: #{width}x#{height}"
  size_msg.each_char_with_index do |char, idx|
    termisu.set_cell(idx, 4, char, fg: Termisu::Color::White)
  end

  # Demonstrate colors
  color_label = "Color demonstration:"
  color_label.each_char_with_index do |char, idx|
    termisu.set_cell(idx, 6, char, fg: Termisu::Color::White)
  end

  colors = [
    Termisu::Color::Black,
    Termisu::Color::Red,
    Termisu::Color::Green,
    Termisu::Color::Yellow,
    Termisu::Color::Blue,
    Termisu::Color::Magenta,
    Termisu::Color::Cyan,
    Termisu::Color::White,
  ]

  colors.each_with_index do |color, idx|
    5.times do |xyz|
      termisu.set_cell(idx * 5 + xyz, 7, '█', fg: color)
    end
  end

  # Demonstrate text attributes
  attr_label = "Text attributes:"
  attr_label.each_char_with_index do |char, idx|
    termisu.set_cell(idx, 9, char, fg: Termisu::Color::White)
  end

  # Bold
  "Bold".each_char_with_index do |char, idx|
    termisu.set_cell(idx, 10, char, fg: Termisu::Color::White, attr: Termisu::Attribute::Bold)
  end

  # Separator
  " | ".each_char_with_index do |char, idx|
    termisu.set_cell(4 + idx, 10, char, fg: Termisu::Color::White)
  end

  # Underline
  "Underline".each_char_with_index do |char, idx|
    termisu.set_cell(7 + idx, 10, char, fg: Termisu::Color::White, attr: Termisu::Attribute::Underline)
  end

  # Separator
  " | ".each_char_with_index do |char, idx|
    termisu.set_cell(16 + idx, 10, char, fg: Termisu::Color::White)
  end

  # Blink
  "Blink".each_char_with_index do |char, idx|
    termisu.set_cell(19 + idx, 10, char, fg: Termisu::Color::White, attr: Termisu::Attribute::Blink)
  end

  # Separator
  " | ".each_char_with_index do |char, idx|
    termisu.set_cell(24 + idx, 10, char, fg: Termisu::Color::White)
  end

  # Reverse
  "Reverse".each_char_with_index do |char, idx|
    termisu.set_cell(27 + idx, 10, char, fg: Termisu::Color::White, attr: Termisu::Attribute::Reverse)
  end

  # Interactive input demo
  input_prompt = "Press any key to continue (will wait 5 seconds)..."
  input_prompt.each_char_with_index do |char, idx|
    termisu.set_cell(idx, 14, char, fg: Termisu::Color::Yellow, attr: Termisu::Attribute::Bold)
  end

  # Initial flush - renders all cells
  termisu.flush

  # Wait for input
  if termisu.wait_for_input(5000)
    if byte = termisu.read_byte
      response = "You pressed: '#{byte.chr}' (byte: #{byte})"
      response.each_char_with_index do |char, idx|
        termisu.set_cell(idx, 15, char, fg: Termisu::Color::Green)
      end
      termisu.flush # Only the new cells are rendered (diff-based)
    end
  else
    timeout_msg = "Timeout! No input received."
    timeout_msg.each_char_with_index do |char, idx|
      termisu.set_cell(idx, 15, char, fg: Termisu::Color::Red)
    end
    termisu.flush
  end

  # Animated goodbye with cursor following the text
  goodbye = "Thanks for trying Termisu! Goodbye! 👋"

  # Show cursor before animation
  termisu.set_cursor(0, 17)
  termisu.flush
  sleep 0.3.seconds

  # Animate text with cursor following
  goodbye.each_char_with_index do |char, idx|
    termisu.set_cell(idx, 17, char, fg: Termisu::Color::Blue, attr: Termisu::Attribute::Bold)
    termisu.set_cursor(idx + 1, 17) # Position cursor after current character
    termisu.flush                   # Each character triggers a flush (shows animation)
    sleep 0.05.seconds
  end

  # Blink cursor a few times at the end
  3.times do
    termisu.hide_cursor
    termisu.flush
    sleep 0.2.seconds
    termisu.set_cursor(goodbye.size, 17)
    termisu.flush
    sleep 0.2.seconds
  end

  # Hide cursor before closing
  termisu.hide_cursor
  termisu.flush

  sleep 1.seconds
ensure
  # Clean shutdown
  termisu.close
end
