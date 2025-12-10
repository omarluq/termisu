# Main Termisu class - Terminal User Interface library.
#
# Provides a clean, minimal API for terminal manipulation by delegating
# all logic to specialized components: Terminal and Reader.
#
# The async event system uses Event::Loop to multiplex multiple event sources:
# - Input events (keyboard, mouse)
# - Resize events (terminal size changes)
# - Timer events (optional, for animation/game loops)
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
  # Sets up terminal I/O, rendering, input reader, and async event system.
  # Automatically enables raw mode and enters alternate screen.
  #
  # The Event::Loop is started with Input and Resize sources by default.
  # Timer source is optional and can be enabled with `enable_timer`.
  def initialize
    Logging.setup

    Log.info { "Initializing Termisu v#{VERSION}" }

    @terminal = Terminal.new
    @reader = Reader.new(@terminal.infd)
    @input_parser = Input::Parser.new(@reader)

    Log.debug { "Terminal size: #{@terminal.size}" }

    @terminal.enable_raw_mode

    # Create async event sources
    @input_source = Event::Source::Input.new(@reader, @input_parser)
    @resize_source = Event::Source::Resize.new(-> { @terminal.size })

    # Timer source is optional (nil by default)
    @timer_source = nil.as(Event::Source::Timer?)

    # Create and configure event loop
    @event_loop = Event::Loop.new
    @event_loop.add_source(@input_source)
    @event_loop.add_source(@resize_source)

    # Start event loop before entering alternate screen
    @event_loop.start

    Log.debug { "Event loop started with sources: #{@event_loop.source_names}" }

    @terminal.enter_alternate_screen

    Log.debug { "Raw mode enabled, alternate screen entered" }
  end

  # Closes Termisu and cleans up all resources.
  #
  # Performs graceful shutdown in the correct order:
  # 1. Stop event loop (stops all sources, closes channel, waits for fibers)
  # 2. Exit alternate screen
  # 3. Disable raw mode
  # 4. Close reader and terminal
  #
  # The event loop is stopped first to ensure fibers that might be using
  # the reader are terminated before the reader is closed.
  def close
    Log.info { "Closing Termisu" }

    # Stop event loop first - this stops all sources and their fibers
    @event_loop.stop
    Log.debug { "Event loop stopped" }

    @terminal.exit_alternate_screen
    @terminal.disable_raw_mode
    @reader.close
    @terminal.close

    Logging.flush
    Logging.close
  end

  # --- Terminal Operations ---

  # Returns terminal size as {width, height}.
  delegate size, to: @terminal

  # Returns true if alternate screen mode is active.
  delegate alternate_screen?, to: @terminal

  # Returns true if raw mode is enabled.
  delegate raw_mode?, to: @terminal

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

  # Polls for the next event, blocking until one is available.
  #
  # This is the recommended way to handle events. Returns structured
  # Event objects (Event::Key, Event::Mouse, Event::Resize, Event::Tick)
  # from the unified Event::Loop channel.
  #
  # Blocks indefinitely until an event arrives.
  #
  # Example:
  # ```
  # loop do
  #   event = termisu.poll_event
  #   case event
  #   when Termisu::Event::Key
  #     break if event.ctrl_c? || event.key.escape?
  #   when Termisu::Event::Resize
  #     termisu.sync # Redraw after resize
  #   when Termisu::Event::Tick
  #     # Animation frame
  #   end
  #   termisu.render
  # end
  # ```
  def poll_event : Event::Any
    @event_loop.output.receive
  end

  # Polls for an event with timeout.
  #
  # Returns an Event or nil if timeout expires.
  #
  # Parameters:
  # - timeout: Maximum time to wait for an event
  #
  # Example:
  # ```
  # if event = termisu.poll_event(100.milliseconds)
  #   # Handle event
  # else
  #   # No event within timeout - do other work
  # end
  # ```
  def poll_event(timeout : Time::Span) : Event::Any?
    select
    when event = @event_loop.output.receive
      event
    when timeout(timeout)
      nil
    end
  end

  # Polls for an event with timeout in milliseconds.
  #
  # Parameters:
  # - timeout_ms: Timeout in milliseconds (0 for non-blocking)
  def poll_event(timeout_ms : Int32) : Event::Any?
    poll_event(timeout_ms.milliseconds)
  end

  # Waits for and returns the next event (blocking).
  #
  # Alias for `poll_event` without timeout. Blocks until an event
  # is available from any source.
  #
  # Example:
  # ```
  # event = termisu.wait_event
  # puts "Got event: #{event}"
  # ```
  def wait_event : Event::Any
    poll_event
  end

  # Yields each event as it becomes available.
  #
  # Blocks waiting for each event. Use this for simple event loops.
  #
  # Example:
  # ```
  # termisu.each_event do |event|
  #   case event
  #   when Termisu::Event::Key
  #     break if event.key.escape?
  #   when Termisu::Event::Tick
  #     # Animation frame
  #   end
  #   termisu.render
  # end
  # ```
  def each_event(&)
    loop do
      yield poll_event
    end
  end

  # Yields each event with timeout between events.
  #
  # If no event arrives within timeout, yields nothing and continues.
  # Useful when you need to do periodic work between events.
  #
  # Parameters:
  # - timeout: Maximum time to wait for each event
  #
  # Example:
  # ```
  # termisu.each_event(100.milliseconds) do |event|
  #   # Process event
  # end
  # # Can do other work between events when timeout expires
  # ```
  def each_event(timeout : Time::Span, &)
    loop do
      if event = poll_event(timeout)
        yield event
      end
    end
  end

  # Yields each event with timeout in milliseconds.
  def each_event(timeout_ms : Int32, &)
    each_event(timeout_ms.milliseconds) { |event| yield event }
  end

  # --- Timer Support ---

  # Enables the timer source for animation and game loops.
  #
  # When enabled, Tick events are emitted at the specified interval.
  # Default interval is 16ms (~60 FPS).
  #
  # Parameters:
  # - interval: Time between tick events (default: 16ms for 60 FPS)
  #
  # Example:
  # ```
  # termisu.enable_timer(16.milliseconds) # 60 FPS
  #
  # termisu.each_event do |event|
  #   case event
  #   when Termisu::Event::Tick
  #     # Update animation state
  #     termisu.render
  #   when Termisu::Event::Key
  #     break if event.key.escape?
  #   end
  # end
  #
  # termisu.disable_timer
  # ```
  def enable_timer(interval : Time::Span = 16.milliseconds) : self
    return self if @timer_source

    timer = Event::Source::Timer.new(interval)
    @timer_source = timer
    @event_loop.add_source(timer)

    Log.debug { "Timer enabled with interval: #{interval}" }

    self
  end

  # Disables the timer source.
  #
  # Stops Tick events from being emitted. Safe to call when timer
  # is already disabled.
  def disable_timer : self
    if timer = @timer_source
      @event_loop.remove_source(timer)
      @timer_source = nil
      Log.debug { "Timer disabled" }
    end

    self
  end

  # Returns true if the timer is currently enabled.
  def timer_enabled? : Bool
    !@timer_source.nil?
  end

  # Sets the timer interval.
  #
  # Can be called while timer is running to change the interval dynamically.
  # Raises if timer is not enabled.
  #
  # Parameters:
  # - interval: New interval between tick events
  #
  # Example:
  # ```
  # termisu.enable_timer
  # termisu.timer_interval = 8.milliseconds # 120 FPS
  # ```
  def timer_interval=(interval : Time::Span) : Time::Span
    if timer = @timer_source
      timer.interval = interval
    else
      raise "Timer not enabled. Call enable_timer first."
    end
  end

  # Returns the current timer interval, or nil if timer is disabled.
  def timer_interval : Time::Span?
    @timer_source.try(&.interval)
  end

  # --- Custom Event Source API ---

  # Adds a custom event source to the event loop.
  #
  # Custom sources must extend `Event::Source` and implement the abstract
  # interface: `#start(channel)`, `#stop`, `#running?`, and `#name`.
  #
  # If the event loop is already running, the source is started immediately.
  # Events from the source will appear in `poll_event` alongside built-in events.
  #
  # Parameters:
  # - source: An Event::Source implementation
  #
  # Returns self for method chaining.
  #
  # Example:
  # ```
  # class NetworkSource < Termisu::Event::Source
  #   def start(output)
  #     # Start listening for network events
  #   end
  #
  #   def stop
  #     # Stop listening
  #   end
  #
  #   def running? : Bool
  #     @running
  #   end
  #
  #   def name : String
  #     "network"
  #   end
  # end
  #
  # termisu.add_event_source(NetworkSource.new)
  # ```
  def add_event_source(source : Event::Source) : self
    @event_loop.add_source(source)
    Log.debug { "Added custom event source: #{source.name}" }
    self
  end

  # Removes a custom event source from the event loop.
  #
  # If the source is running, it will be stopped before removal.
  # Removing a source that isn't registered is a no-op.
  #
  # Parameters:
  # - source: The Event::Source to remove
  #
  # Returns self for method chaining.
  def remove_event_source(source : Event::Source) : self
    @event_loop.remove_source(source)
    Log.debug { "Removed custom event source: #{source.name}" }
    self
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
