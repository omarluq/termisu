module Termisu::FFI
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
    end
  end
end
