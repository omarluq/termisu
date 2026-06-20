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
alias Termisu::Event::Any = Termisu::Event::Key |
                            Termisu::Event::Mouse |
                            Termisu::Event::Resize |
                            Termisu::Event::Tick |
                            Termisu::Event::ModeChange |
                            Termisu::Event::Preedit

# Preedit text from the input method during composition (e.g. partial Hangul
# syllable as jamo are typed). The TUI should render this at the current cursor
# position, typically with an underline or other composing indicator (not
# yet committed to the buffer). When the user completes the composition (e.g.
# presses space or the next key that commits), the terminal will send the
# final committed character(s) as normal Key event(s) with 'char', and the
# preedit will be cleared (a Preedit with empty text or subsequent commit).
#
# Note: Support for actually receiving Preedit events depends on the terminal
# emulator supporting client-side preedit reporting via the keyboard protocol
# (e.g. Kitty with report_text) or other mechanisms. termisu delivers them if
# the terminal sends the appropriate sequences; otherwise only committed chars
# arrive (as before).
struct Termisu::Event::Preedit
  getter text : String

  def initialize(@text : String)
  end
end
