# Terminal resize event.
#
# Generated when the terminal window size changes (SIGWINCH).
# Optionally includes previous dimensions for incremental resize handling.
#
# Example:
# ```
# event = termisu.poll_event
# if event.is_a?(Termisu::Event::Resize)
#   puts "Terminal resized to #{event.width}x#{event.height}"
#   if event.changed?
#     puts "Changed from #{event.old_width}x#{event.old_height}"
#   end
#   termisu.sync # Force full redraw
# end
# ```
struct Termisu::Event::Resize
  # New terminal width in columns.
  getter width : Int32

  # New terminal height in rows.
  getter height : Int32

  # Previous terminal width in columns (nil if unknown or first resize).
  getter old_width : Int32?

  # Previous terminal height in rows (nil if unknown or first resize).
  getter old_height : Int32?

  def initialize(
    @width : Int32,
    @height : Int32,
    @old_width : Int32? = nil,
    @old_height : Int32? = nil,
  )
  end

  # Returns true if the dimensions have changed from previous values.
  #
  # Returns true if:
  # - Previous dimensions are unknown (nil)
  # - Width or height differs from previous values
  def changed? : Bool
    old_w = @old_width
    old_h = @old_height

    return true if old_w.nil? || old_h.nil?

    old_w != @width || old_h != @height
  end
end
