# Events module for terminal input handling.
#
# Provides structured event types for keyboard input, mouse events,
# and terminal resize events.
#
# Example:
# ```
# termisu = Termisu.new
# begin
#   loop do
#     if event = termisu.poll_event(100)
#       case event
#       when Termisu::Events::Key
#         break if event.ctrl_c? || event.key.escape?
#         puts "Key: #{event.key}"
#       when Termisu::Events::Mouse
#         puts "Mouse: #{event.x},#{event.y} button=#{event.button}"
#       when Termisu::Events::Resize
#         puts "Resize: #{event.width}x#{event.height}"
#       end
#     end
#   end
# ensure
#   termisu.close
# end
# ```
module Termisu::Events
end

# Union type for all terminal events.
alias Termisu::Event = Termisu::Events::Key | Termisu::Events::Mouse | Termisu::Events::Resize

require "./events/*"
