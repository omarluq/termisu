# Keyboard input event.
#
# Contains the key pressed and any modifier keys that were held.
#
# Example:
# ```
# event = termisu.poll_event
# if event.is_a?(Termisu::Events::Key)
#   if event.ctrl_c?
#     puts "Ctrl+C pressed, exiting..."
#   elsif event.key.escape?
#     puts "Escape pressed"
#   end
# end
# ```
struct Termisu::Events::Key
  # The key that was pressed.
  getter key : Termisu::Key

  # Modifier keys held during the keypress.
  getter modifiers : Modifier

  def initialize(@key : Termisu::Key, @modifiers : Modifier = Modifier::None)
  end

  # Returns true if Ctrl modifier was held.
  def ctrl? : Bool
    modifiers.ctrl?
  end

  # Returns true if Alt modifier was held.
  def alt? : Bool
    modifiers.alt?
  end

  # Returns true if Shift modifier was held.
  def shift? : Bool
    modifiers.shift?
  end

  # Returns true if Meta modifier was held.
  def meta? : Bool
    modifiers.meta?
  end

  # Returns true if this is Ctrl+C.
  def ctrl_c? : Bool
    key.lower_c? && ctrl? && !alt? && !shift?
  end

  # Returns true if this is Ctrl+D.
  def ctrl_d? : Bool
    key.lower_d? && ctrl? && !alt? && !shift?
  end

  # Returns true if this is Ctrl+Z.
  def ctrl_z? : Bool
    key.lower_z? && ctrl? && !alt? && !shift?
  end

  # Returns true if this is Ctrl+Q.
  def ctrl_q? : Bool
    key.lower_q? && ctrl? && !alt? && !shift?
  end

  # Returns the character for this key, if printable.
  def char : Char?
    key.to_char
  end
end
