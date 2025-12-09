# Mouse input event.
#
# Contains mouse position, button state, and modifiers.
# Supports all mouse protocols (X10, Normal, SGR, URXVT).
#
# Example:
# ```
# event = termisu.poll_event
# if event.is_a?(Termisu::Event::Mouse)
#   case event.button
#   when .left?
#     puts "Left click at #{event.x},#{event.y}"
#   when .wheel_up?
#     puts "Scroll up"
#   when .release?
#     puts "Button released"
#   end
# end
# ```
struct Termisu::Event::Mouse
  # X coordinate (column, 1-based).
  getter x : Int32

  # Y coordinate (row, 1-based).
  getter y : Int32

  # Mouse button that triggered the event.
  getter button : MouseButton

  # Modifier keys held during the mouse event.
  getter modifiers : Input::Modifier

  # Whether this is a motion event (mouse moved while button held).
  getter? motion : Bool

  def initialize(
    @x : Int32,
    @y : Int32,
    @button : MouseButton,
    @modifiers : Input::Modifier = Input::Modifier::None,
    @motion : Bool = false,
  )
  end

  # Returns true if this is a button press event.
  def press? : Bool
    !button.release? && !motion?
  end

  # Returns true if this is a wheel scroll event.
  def wheel? : Bool
    button.wheel_up? || button.wheel_down? ||
      button.wheel_left? || button.wheel_right?
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

  # Returns true if Meta/Super/Windows modifier was held.
  def meta? : Bool
    modifiers.meta?
  end
end

# Mouse button types.
enum Termisu::Event::MouseButton
  # No button (used for motion-only events).
  None

  # Left mouse button (button 1).
  Left

  # Middle mouse button (button 2).
  Middle

  # Right mouse button (button 3).
  Right

  # Scroll wheel up.
  WheelUp

  # Scroll wheel down.
  WheelDown

  # Scroll wheel left (horizontal scroll).
  WheelLeft

  # Scroll wheel right (horizontal scroll).
  WheelRight

  # Button release event.
  Release

  # Extra button 4 (forward).
  Button4

  # Extra button 5 (back).
  Button5

  # Decodes a button from the Cb value in mouse protocols.
  #
  # Low 2 bits encode the button:
  # - 0 = Left
  # - 1 = Middle
  # - 2 = Right
  # - 3 = Release
  #
  # Bit 6 (64) indicates wheel events:
  # - 64 = Wheel Up
  # - 65 = Wheel Down
  # - 66 = Wheel Left
  # - 67 = Wheel Right
  def self.from_cb(cb : Int32) : MouseButton
    # Check for wheel events first (bit 6 set)
    if (cb & MouseProtocol::WHEEL_BIT) != 0
      case cb & MouseProtocol::BUTTON_MASK
      when 0 then WheelUp
      when 1 then WheelDown
      when 2 then WheelLeft
      when 3 then WheelRight
      else        None
      end
    else
      # Regular button
      case cb & MouseProtocol::BUTTON_MASK
      when 0 then Left
      when 1 then Middle
      when 2 then Right
      when 3 then Release
      else        None
      end
    end
  end
end

# Mouse protocol bit masks for Cb byte decoding.
# Defined outside the enum to avoid type coercion issues.
module Termisu::Event::MouseProtocol
  # Low 2 bits encode button number.
  BUTTON_MASK = 3

  # Bit 6 indicates wheel events.
  WHEEL_BIT = 64
end
