# Terminal resize event.
#
# Generated when the terminal window size changes (SIGWINCH).
#
# Example:
# ```
# event = termisu.poll_event
# if event.is_a?(Termisu::Events::Resize)
#   puts "Terminal resized to #{event.width}x#{event.height}"
#   termisu.sync # Force full redraw
# end
# ```
struct Termisu::Events::Resize
  # New terminal width in columns.
  getter width : Int32

  # New terminal height in rows.
  getter height : Int32

  def initialize(@width : Int32, @height : Int32)
  end
end
