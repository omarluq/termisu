require "../src/termisu"

termisu = Termisu.new

begin
  # Set individual cells with colors and attributes
  attr = Termisu::Attribute::Bold | Termisu::Attribute::Underline
  termisu.set_cell(0, 0, 'H', fg: Termisu::Color::Red, attr: attr)
  termisu.set_cell(1, 0, 'i', fg: Termisu::Color::Green, attr: attr)

  # Position and show cursor
  termisu.set_cursor(3, 0)

  # Flush renders only changed cells (diff-based)
  termisu.flush

  # Wait for input
  if termisu.wait_for_input(5000)
    byte = termisu.read_byte
    if byte
      msg = "You pressed: '#{byte.chr}' (byte: #{byte})"
      msg.each_char_with_index do |char, idx|
        termisu.set_cell(idx, 2, char, Termisu::Color::White, attr: attr)
        termisu.set_cursor(idx+1, 2)
        termisu.flush
        sleep 0.01.seconds
      end
    end
  end
ensure
  sleep 1.seconds
  termisu.close
end
