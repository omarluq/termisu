# Terminal mode change event.
#
# Generated when the terminal mode is changed via `set_mode` or `with_mode`.
# Includes both the new mode and previous mode for tracking transitions.
#
# Example:
# ```
# termisu.each_event do |event|
#   case event
#   when Termisu::Event::ModeChange
#     puts "Mode changed: #{event.previous_mode} -> #{event.mode}"
#     if event.to_raw?
#       # Re-entering TUI mode
#     elsif event.from_raw?
#       # Leaving TUI mode
#     end
#   end
# end
# ```
struct Termisu::Event::ModeChange
  # The new terminal mode.
  getter mode : Terminal::Mode

  # The previous terminal mode (nil if this is the first mode change).
  getter previous_mode : Terminal::Mode?

  def initialize(
    @mode : Terminal::Mode,
    @previous_mode : Terminal::Mode? = nil,
  )
  end

  # Returns true if transitioning to raw mode.
  def to_raw? : Bool
    @mode.none?
  end

  # Returns true if transitioning from raw mode.
  def from_raw? : Bool
    @previous_mode.try(&.none?) || false
  end

  # Returns true if the mode actually changed.
  #
  # Returns false if:
  # - Previous mode is nil (first mode assignment, not a change)
  # - Previous mode equals current mode
  def changed? : Bool
    prev = @previous_mode
    return false if prev.nil?
    prev != @mode
  end

  # Returns true if transitioning to a user-interactive mode.
  #
  # User-interactive modes have canonical input or echo enabled,
  # where the terminal driver handles input rather than the application.
  def to_user_interactive? : Bool
    @mode.canonical? || @mode.echo?
  end

  # Returns true if transitioning from a user-interactive mode.
  def from_user_interactive? : Bool
    if prev = @previous_mode
      prev.canonical? || prev.echo?
    else
      false
    end
  end
end
