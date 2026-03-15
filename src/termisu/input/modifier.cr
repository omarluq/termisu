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
enum Termisu::Input::Modifier : UInt8
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
    from_bits(
      code - 1,
      shift_bit: ModifierBits::XTERM_SHIFT,
      alt_bit: ModifierBits::XTERM_ALT,
      ctrl_bit: ModifierBits::XTERM_CTRL,
      meta_bit: ModifierBits::XTERM_META,
    )
  end

  # Decodes mouse button modifiers from the Cb byte.
  #
  # In mouse protocols, modifiers are encoded as:
  # - Bit 2 (4) = Shift
  # - Bit 3 (8) = Meta/Alt
  # - Bit 4 (16) = Control
  def self.from_mouse_cb(cb : Int32) : Modifier
    from_bits(
      cb,
      shift_bit: ModifierBits::MOUSE_SHIFT,
      alt_bit: ModifierBits::MOUSE_ALT,
      ctrl_bit: ModifierBits::MOUSE_CTRL,
    )
  end

  private def self.from_bits(
    value : Int32,
    *,
    shift_bit : Int32,
    alt_bit : Int32,
    ctrl_bit : Int32,
    meta_bit : Int32? = nil,
  ) : Modifier
    mod = None
    mod |= Shift if (value & shift_bit) != 0
    mod |= Alt if (value & alt_bit) != 0
    mod |= Ctrl if (value & ctrl_bit) != 0
    mod |= Meta if meta_bit && (value & meta_bit) != 0
    mod
  end
end

# Modifier bit masks for protocol decoding.
# Defined outside the enum to avoid type coercion issues.
module Termisu::Input::ModifierBits
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
