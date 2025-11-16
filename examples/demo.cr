require "../src/termisu"

# Demo showcasing Termisu's clean API
termisu = Termisu.new

# Clear and position cursor
termisu.clear_screen
termisu.move_cursor(0, 0)

# Display welcome message with styling
termisu.enable_bold
termisu.foreground = 2 # Green
termisu.write("╔════════════════════════════════════════╗")
termisu.move_cursor(0, 1)
termisu.write("║     Welcome to Termisu Demo! 🎨        ║")
termisu.move_cursor(0, 2)
termisu.write("╚════════════════════════════════════════╝")
termisu.reset_attributes
termisu.flush

# Show terminal size
width, height = termisu.size
termisu.move_cursor(0, 4)
termisu.write("Terminal size: #{width}x#{height}")
termisu.flush

# Demonstrate colors
termisu.move_cursor(0, 6)
termisu.write("Color demonstration:")
8.times do |idx|
  termisu.move_cursor(idx * 5, 7)
  termisu.foreground = idx
  termisu.write("█████")
end
termisu.reset_attributes
termisu.flush

# Demonstrate text attributes
termisu.move_cursor(0, 9)
termisu.write("Text attributes:")
termisu.move_cursor(0, 10)
termisu.enable_bold
termisu.write("Bold")
termisu.reset_attributes
termisu.write(" | ")
termisu.enable_underline
termisu.write("Underline")
termisu.reset_attributes
termisu.write(" | ")
termisu.enable_blink
termisu.write("Blink")
termisu.reset_attributes
termisu.write(" | ")
termisu.enable_reverse
termisu.write("Reverse")
termisu.reset_attributes
termisu.flush

# Show cursor manipulation
termisu.move_cursor(0, 12)
termisu.write("Cursor: ")
termisu.hide_cursor
termisu.write("Hidden... ")
termisu.flush
sleep 1.5.seconds
termisu.show_cursor
termisu.write("Visible!")
termisu.flush

# Interactive input demo
termisu.move_cursor(0, 14)
termisu.enable_bold
termisu.foreground = 3 # Yellow
termisu.write("Press any key to continue (will wait 5 seconds)...")
termisu.reset_attributes
termisu.flush

if termisu.wait_for_input(5000)
  if byte = termisu.read_byte
    termisu.move_cursor(0, 15)
    termisu.foreground = 2 # Green
    termisu.write("You pressed: '#{byte.chr}' (byte: #{byte})")
    termisu.reset_attributes
    termisu.flush
  end
else
  termisu.move_cursor(0, 15)
  termisu.foreground = 1 # Red
  termisu.write("Timeout! No input received.")
  termisu.reset_attributes
  termisu.flush
end

# Animated goodbye
termisu.move_cursor(0, 17)
termisu.enable_bold
termisu.foreground = 4 # Blue
goodbye = "Thanks for trying Termisu! Goodbye! 👋"
goodbye.each_char do |char|
  termisu.write(char.to_s)
  termisu.flush
  sleep 0.05.seconds
end
termisu.reset_attributes
termisu.flush

sleep 2.seconds

# Clean shutdown
termisu.close
