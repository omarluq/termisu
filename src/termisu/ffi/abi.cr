module Termisu::FFI
  # Inline capacity (bytes) for ABI::Event preedit text. Composing strings are
  # short (a handful of codepoints); longer preedit is truncated on a boundary.
  PREEDIT_TEXT_CAPACITY = 32

  lib ABI
    struct Color
      mode : UInt8
      index : Int32
      r : UInt8
      g : UInt8
      b : UInt8
    end

    struct CellStyle
      fg : Color
      bg : Color
      attr : UInt16
    end

    struct Size
      width : Int32
      height : Int32
    end

    struct Event
      event_type : UInt8
      modifiers : UInt8
      reserved : UInt16

      key_code : Int32
      key_char : Int32

      mouse_x : Int32
      mouse_y : Int32
      mouse_button : Int32
      mouse_motion : UInt8

      resize_width : Int32
      resize_height : Int32
      resize_old_width : Int32
      resize_old_height : Int32
      resize_has_old : UInt8

      tick_frame : UInt64
      tick_elapsed_ns : Int64
      tick_delta_ns : Int64
      tick_missed_ticks : UInt64

      mode_current : UInt32
      mode_previous : UInt32
      mode_has_previous : UInt8

      # IME preedit (composing) text, inline UTF-8. preedit_len is the number of
      # valid bytes in preedit_text; the text is truncated on a codepoint
      # boundary if it would exceed the buffer. An empty preedit (len 0) means
      # composition was cleared. Appended last so existing field offsets are
      # unchanged across this ABI revision.
      preedit_len : UInt8
      preedit_text : UInt8[PREEDIT_TEXT_CAPACITY]
    end
  end
end
