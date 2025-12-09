# Keyboard modifier flags for input events.
#
# Modifiers can be combined using bitwise OR (|).
# XTerm encodes modifiers as: code = 1 + (shift*1 + alt*2 + ctrl*4 + meta*8)
#
# Example:
# ```
# event = termisu.poll_event
# if event.is_a?(Termisu::Event::Key)
#   if event.modifiers.ctrl? && event.key.lower_c?
#     puts "Ctrl+C pressed!"
#   end
# end
# ```
@[Flags]
enum Termisu::Modifier : UInt8
  # No modifiers
  None = 0

  # Shift key
  Shift = 1

  # Alt/Option key
  Alt = 2

  # Control key
  Ctrl = 4

  # Meta/Super/Windows key
  Meta = 8

  # Decodes an XTerm modifier code to Modifier flags.
  #
  # XTerm encoding: code = 1 + (shift*1 + alt*2 + ctrl*4 + meta*8)
  # So we subtract 1 to get the raw flags.
  def self.from_xterm_code(code : Int32) : Modifier
    return None if code <= 1
    raw = code - 1
    mod = None
    mod |= Shift if (raw & ModifierBits::XTERM_SHIFT) != 0
    mod |= Alt if (raw & ModifierBits::XTERM_ALT) != 0
    mod |= Ctrl if (raw & ModifierBits::XTERM_CTRL) != 0
    mod |= Meta if (raw & ModifierBits::XTERM_META) != 0
    mod
  end

  # Decodes mouse button modifiers from the Cb byte.
  #
  # In mouse protocols, modifiers are encoded as:
  # - Bit 2 (4) = Shift
  # - Bit 3 (8) = Meta/Alt
  # - Bit 4 (16) = Control
  def self.from_mouse_cb(cb : Int32) : Modifier
    mod = None
    mod |= Shift if (cb & ModifierBits::MOUSE_SHIFT) != 0
    mod |= Alt if (cb & ModifierBits::MOUSE_ALT) != 0
    mod |= Ctrl if (cb & ModifierBits::MOUSE_CTRL) != 0
    mod
  end
end

# Modifier bit masks for protocol decoding.
# Defined outside the enum to avoid type coercion issues.
module Termisu::ModifierBits
  # XTerm modifier bit masks (used in CSI sequences).
  # XTerm encoding: code = 1 + (shift*1 + alt*2 + ctrl*4 + meta*8)
  XTERM_SHIFT = 1
  XTERM_ALT   = 2
  XTERM_CTRL  = 4
  XTERM_META  = 8

  # Mouse protocol modifier bit masks (used in Cb byte).
  # Different bit positions than XTerm keyboard modifiers.
  MOUSE_SHIFT =  4 # Bit 2
  MOUSE_ALT   =  8 # Bit 3
  MOUSE_CTRL  = 16 # Bit 4
end
