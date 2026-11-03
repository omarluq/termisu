{% if flag?(:win32) %}
  # Internal console bindings, kept separate so native contracts can be tested
  # without starting Termisu's input source or borrowing standard handles.
  module Termisu::System::Console
    @[Link("kernel32")]
    lib C
      struct Coord
        x : Int16
        y : Int16
      end

      struct SmallRect
        left : Int16
        top : Int16
        right : Int16
        bottom : Int16
      end

      struct ScreenBufferInfo
        size : Coord
        cursor_position : Coord
        attributes : UInt16
        window : SmallRect
        maximum_window_size : Coord
      end

      # INPUT_RECORD's union is aligned to DWORD and its largest member is
      # KEY_EVENT_RECORD; the remaining event types are not decoded here.
      struct KeyEventRecord
        key_down : LibC::BOOL
        repeat_count : UInt16
        virtual_key_code : UInt16
        virtual_scan_code : UInt16
        unicode_char : UInt16
        control_key_state : LibC::DWORD
      end

      struct InputRecord
        event_type : UInt16
        key_event : KeyEventRecord
      end

      KEY_EVENT = 0x0001_u16

      ENABLE_EXTENDED_FLAGS  = 0x0080_u32
      ENABLE_QUICK_EDIT_MODE = 0x0040_u32

      fun GetConsoleScreenBufferInfo(handle : LibC::HANDLE, info : ScreenBufferInfo*) : LibC::BOOL
      fun GetNumberOfConsoleInputEvents(handle : LibC::HANDLE, count : LibC::DWORD*) : LibC::BOOL
      fun ReadConsoleInputW(handle : LibC::HANDLE, buffer : InputRecord*, length : LibC::DWORD, read : LibC::DWORD*) : LibC::BOOL
    end
  end
{% end %}
