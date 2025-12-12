require "../src/termisu"

termisu = Termisu.new

begin
  # Set individual cells with colors and attributes
  attr = Termisu::Attribute::Bold | Termisu::Attribute::Underline
  termisu.set_cell(0, 0, 'H', fg: Termisu::Color.red, attr: attr)
  termisu.set_cell(1, 0, 'i', fg: Termisu::Color.green, attr: attr)

  # Demonstrate strikethrough attribute
  strike_attr = Termisu::Attribute::Strikethrough
  "Strikethrough".each_char_with_index do |char, idx|
    termisu.set_cell(idx, 1, char, fg: Termisu::Color.yellow, attr: strike_attr)
  end

  # Position and show cursor
  termisu.set_cursor(14, 1)

  # Render only changed cells (diff-based)
  termisu.render

  # Wait for input
  if termisu.wait_for_input(5000)
    byte = termisu.read_byte
    if byte
      msg = "You pressed: '#{byte.chr}' (byte: #{byte})"
      msg.each_char_with_index do |char, idx|
        termisu.set_cell(idx, 3, char, Termisu::Color.white, attr: attr)
        termisu.set_cursor(idx + 1, 3)
        termisu.render
        sleep 0.01.seconds
      end
    end
  end
ensure
  sleep 1.seconds
  termisu.close
end
