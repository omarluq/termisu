# Events module for terminal input handling.
#
# Provides structured event types for keyboard input, mouse events,
# terminal resize events, and timer tick events.
#
# Event types are namespaced under `Termisu::Event::*` and the union type
# `Termisu::Event::Any` is used for type annotations and pattern matching.
#
# Example:
# ```
# termisu = Termisu.new
# begin
#   termisu.each_event do |event|
#     case event
#     when Termisu::Event::Key
#       break if event.ctrl_c? || event.key.escape?
#       puts "Key: #{event.key}"
#     when Termisu::Event::Mouse
#       puts "Mouse: #{event.x},#{event.y} button=#{event.button}"
#     when Termisu::Event::Resize
#       puts "Resize: #{event.width}x#{event.height}"
#     when Termisu::Event::Tick
#       puts "Tick: frame=#{event.frame}"
#     when Termisu::Event::ModeChange
#       puts "Mode: #{event.previous_mode} -> #{event.mode}"
#     end
#   end
# ensure
#   termisu.close
# end
# ```
module Termisu::Event
end

require "./event/*"
require "./event/source/*"

# Union type for all terminal events.
# Use Event::Any for type annotations and collections.
# Individual event types (Event::Key, Event::Mouse, etc.) work in case statements.
alias Termisu::Event::Any = Termisu::Event::Key | Termisu::Event::Mouse | Termisu::Event::Resize | Termisu::Event::Tick | Termisu::Event::ModeChange
