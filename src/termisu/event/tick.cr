# Timer tick event.
#
# Generated at regular intervals when the timer is enabled.
# Provides timing information for animations and game loops.
#
# Example:
# ```
# termisu.enable_timer(16.milliseconds) # ~60 FPS
#
# loop do
#   if event = termisu.poll_event(100)
#     case event
#     when Termisu::Event::Tick
#       # Use delta for frame-rate independent animations
#       position += velocity * event.delta.total_seconds
#       puts "Frame #{event.frame}, elapsed: #{event.elapsed}"
#     when Termisu::Event::Key
#       break if event.key.escape?
#     end
#   end
#   termisu.render
# end
# ```
struct Termisu::Event::Tick
  # Total time elapsed since the timer was started.
  getter elapsed : Time::Span

  # Time since the previous tick event.
  # Useful for frame-rate independent animations.
  getter delta : Time::Span

  # Frame counter (starts at 0, increments each tick).
  getter frame : UInt64

  def initialize(
    @elapsed : Time::Span,
    @delta : Time::Span,
    @frame : UInt64,
  )
  end
end
