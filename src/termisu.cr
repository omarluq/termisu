# Main Termisu class - Terminal User Interface library.
#
# Provides a clean, minimal API for terminal manipulation by delegating
# all logic to specialized components: Terminal and Reader.
#
# Example:
# ```
# termisu = Termisu.new
#
# # Set cells with colors and attributes
# termisu.set_cell(10, 5, 'H', fg: Color.red, bg: Color.black, attr: Attribute::Bold)
# termisu.set_cell(11, 5, 'i', fg: Color.green)
# termisu.set_cell(12, 5, '!', fg: Color.blue)
#
# # Render applies changes (diff-based rendering)
# termisu.render
#
# termisu.close
# ```
class Termisu
  # Initializes Termisu with all required components.
  #
  # Sets up terminal I/O, rendering, and input reader.
  # Automatically enables raw mode and enters alternate screen.
  def initialize
    Logging.setup

    Log.info { "Initializing Termisu v#{VERSION}" }

    @terminal = Terminal.new
    @reader = Reader.new(@terminal.infd)

    Log.debug { "Terminal size: #{@terminal.size}" }

    @terminal.enable_raw_mode
    @terminal.enter_alternate_screen

    Log.debug { "Raw mode enabled, alternate screen entered" }
  end

  # Closes Termisu and cleans up all resources.
  #
  # Exits alternate screen, disables raw mode, and closes all components.
  def close
    Log.info { "Closing Termisu" }

    @terminal.exit_alternate_screen
    @terminal.disable_raw_mode
    @reader.close
    @terminal.close

    Logging.flush
    Logging.close
  end

  # --- Terminal Operations ---

  # Returns the underlying terminal for direct access.
  getter terminal : Terminal

  # Returns terminal size as {width, height}.
  delegate size, to: @terminal

  # --- Cell Buffer Operations ---

  # Sets a cell at the specified position.
  #
  # Parameters:
  # - x: Column position (0-based)
  # - y: Row position (0-based)
  # - ch: Character to display
  # - fg: Foreground color (default: white)
  # - bg: Background color (default: default terminal color)
  # - attr: Text attributes (default: None)
  #
  # Returns false if coordinates are out of bounds.
  #
  # Example:
  # ```
  # termisu.set_cell(10, 5, 'A', fg: Color.red, attr: Attribute::Bold)
  # termisu.render # Apply changes
  # ```
  delegate set_cell, to: @terminal

  # Clears the cell buffer (fills with spaces).
  #
  # Note: This clears the buffer, not the screen. Call render() to apply.
  def clear
    @terminal.clear_cells
  end

  # Renders cell buffer changes to the screen.
  #
  # Only cells that have changed since the last render are redrawn (diff-based).
  # This is more efficient than clear_screen + write for partial updates.
  delegate render, to: @terminal

  # Forces a full redraw of all cells.
  #
  # Useful after terminal resize or screen corruption.
  delegate sync, to: @terminal

  # --- Cursor Control ---

  # Sets cursor position and makes it visible.
  # Hides the cursor (rendered on next render()).
  # Shows the cursor (rendered on next render()).
  delegate set_cursor, hide_cursor, show_cursor, to: @terminal

  # --- Input Operations ---

  delegate read_byte, # Reads single byte, returns UInt8?
    read_bytes,       # Reads count bytes, returns Bytes?
    peek_byte,        # Peeks next byte without consuming, returns UInt8?
    to: @reader

  # Checks if input data is available.
  def input_available? : Bool
    @reader.available?
  end

  # Waits for input data with a timeout in milliseconds.
  def wait_for_input(timeout_ms : Int32) : Bool
    @reader.wait_for_data(timeout_ms)
  end

  # --- Event-Based Input API ---

  # Lazy-initialized input parser for event-based input.
  @input_parser : Input::Parser?

  # Returns the input parser, creating it if needed.
  private def input_parser : Input::Parser
    @input_parser ||= Input::Parser.new(@reader)
  end

  # Polls for an input event with optional timeout.
  #
  # This is the recommended way to handle keyboard and mouse input. Returns
  # structured Event objects (Event::Key, Event::Mouse, Event::Resize, Event::Tick)
  # instead of raw bytes.
  #
  # Parameters:
  # - timeout_ms: Timeout in milliseconds (-1 for blocking, 0 for non-blocking)
  #
  # Returns an Event or nil if timeout/no data.
  #
  # Example:
  # ```
  # loop do
  #   if event = termisu.poll_event(100)
  #     case event
  #     when Termisu::Event::Key
  #       break if event.ctrl_c? || event.key.escape?
  #       puts "Key: #{event.key}"
  #     when Termisu::Event::Mouse
  #       puts "Mouse: #{event.x},#{event.y}"
  #     end
  #   end
  #   termisu.render
  # end
  # ```
  def poll_event(timeout_ms : Int32 = -1) : Event::Any?
    input_parser.poll_event(timeout_ms)
  end

  # Waits for and returns the next input event (blocking).
  #
  # This method blocks until an event is available.
  #
  # Example:
  # ```
  # event = termisu.wait_event
  # puts "Got event: #{event}"
  # ```
  def wait_event : Event::Any
    loop do
      if event = poll_event(-1)
        return event
      end
    end
  end

  # Yields each event as it becomes available.
  #
  # This is a convenient way to process events in a loop.
  # Use timeout_ms to control polling behavior.
  #
  # Example:
  # ```
  # termisu.each_event(100) do |event|
  #   case event
  #   when Termisu::Event::Key
  #     break if event.key.escape?
  #   end
  #   termisu.render
  # end
  # ```
  def each_event(timeout_ms : Int32 = -1, &)
    loop do
      if event = poll_event(timeout_ms)
        yield event
      end
    end
  end

  # --- Mouse Support ---

  # Enables mouse input tracking.
  #
  # Once enabled, mouse events will be reported via poll_event.
  # Supports SGR extended protocol (mode 1006) for large terminals
  # and falls back to normal mode (1000) for compatibility.
  #
  # Example:
  # ```
  # termisu.enable_mouse
  # loop do
  #   if event = termisu.poll_event(100)
  #     case event
  #     when Termisu::Event::Mouse
  #       puts "Click at #{event.x},#{event.y}"
  #     end
  #   end
  # end
  # termisu.disable_mouse
  # ```
  delegate enable_mouse, disable_mouse, mouse_enabled?, to: @terminal

  # --- Enhanced Keyboard Support ---

  # Enables enhanced keyboard protocol for disambiguated key reporting.
  #
  # In standard terminal mode, certain keys are indistinguishable:
  # - Tab sends the same byte as Ctrl+I (0x09)
  # - Enter sends the same byte as Ctrl+M (0x0D)
  # - Backspace may send the same byte as Ctrl+H (0x08)
  #
  # Enhanced mode enables the Kitty keyboard protocol and/or modifyOtherKeys,
  # which report keys in a way that preserves the distinction.
  #
  # Note: Not all terminals support these protocols. Unsupported terminals
  # will silently ignore the escape sequences and continue with legacy mode.
  # Supported terminals include: Kitty, WezTerm, foot, Ghostty, recent xterm.
  #
  # Example:
  # ```
  # termisu.enable_enhanced_keyboard
  # loop do
  #   if event = termisu.poll_event(100)
  #     case event
  #     when Termisu::Event::Key
  #       # Now Ctrl+I and Tab are distinguishable!
  #       if event.ctrl? && event.key.lower_i?
  #         puts "Ctrl+I pressed"
  #       elsif event.key.tab?
  #         puts "Tab pressed"
  #       end
  #     end
  #   end
  # end
  # termisu.disable_enhanced_keyboard
  # ```
  delegate enable_enhanced_keyboard, disable_enhanced_keyboard, enhanced_keyboard?, to: @terminal
end

require "./termisu/*"
