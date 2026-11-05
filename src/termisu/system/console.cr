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
      # KEY_EVENT_RECORD. Mouse events use the same 16-byte union storage.
      struct KeyEventRecord
        key_down : LibC::BOOL
        repeat_count : UInt16
        virtual_key_code : UInt16
        virtual_scan_code : UInt16
        unicode_char : UInt16
        control_key_state : LibC::DWORD
      end

      struct MouseEventRecord
        position : Coord
        button_state : LibC::DWORD
        control_key_state : LibC::DWORD
        event_flags : LibC::DWORD
      end

      struct InputRecord
        event_type : UInt16
        key_event : KeyEventRecord
      end

      KEY_EVENT   = 0x0001_u16
      MOUSE_EVENT = 0x0002_u16

      MOUSE_MOVED    = 0x0001_u32
      DOUBLE_CLICK   = 0x0002_u32
      MOUSE_WHEELED  = 0x0004_u32
      MOUSE_HWHEELED = 0x0008_u32

      ENABLE_MOUSE_INPUT     = 0x0010_u32
      ENABLE_EXTENDED_FLAGS  = 0x0080_u32
      ENABLE_QUICK_EDIT_MODE = 0x0040_u32

      fun GetConsoleScreenBufferInfo(handle : LibC::HANDLE, info : ScreenBufferInfo*) : LibC::BOOL
      fun GetNumberOfConsoleInputEvents(handle : LibC::HANDLE, count : LibC::DWORD*) : LibC::BOOL
      fun ReadConsoleInputW(handle : LibC::HANDLE, buffer : InputRecord*, length : LibC::DWORD, read : LibC::DWORD*) : LibC::BOOL
      fun WriteConsoleInputW(handle : LibC::HANDLE, buffer : InputRecord*, length : LibC::DWORD, written : LibC::DWORD*) : LibC::BOOL
      fun WriteConsoleW(handle : LibC::HANDLE, buffer : Void*, length : LibC::DWORD, written : LibC::DWORD*, reserved : Void*) : LibC::BOOL
      fun CreateEventW(attributes : LibC::SECURITY_ATTRIBUTES*, manual_reset : LibC::BOOL, initial_state : LibC::BOOL, name : UInt16*) : LibC::HANDLE
      fun SetEvent(handle : LibC::HANDLE) : LibC::BOOL
      fun WaitForMultipleObjects(count : UInt32, handles : LibC::HANDLE*, wait_all : LibC::BOOL, timeout_ms : UInt32) : UInt32
    end

    @[Link("user32")]
    lib Keyboard
      fun VkKeyScanW(character : UInt16) : Int16
    end

    alias RecordReader = Proc(LibC::HANDLE, Pointer(C::InputRecord), UInt32, Pointer(UInt32), UInt16, LibC::BOOL)

    # ReadConsoleInputExW has no import library; Microsoft documents this kernel32 export.
    READ_RECORDS = begin
      name = "kernel32.dll\0".to_utf16
      if LibC.GetModuleHandleExW(LibC::GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT, name, out library) == 0
        raise IO::Error.from_winerror("GetModuleHandleExW(kernel32)")
      end
      address = LibC.GetProcAddress(library, "ReadConsoleInputExW")
      raise IO::Error.from_winerror("GetProcAddress(ReadConsoleInputExW)") if address.null?
      RecordReader.new(address, Pointer(Void).null)
    end

    def self.read_records(input : LibC::HANDLE, records : Slice(C::InputRecord), *, remove : Bool = true) : Int32
      count = 0_u32
      flags = remove ? 0x0002_u16 : 0x0003_u16 # NOWAIT, optionally NOREMOVE
      if READ_RECORDS.call(input, records.to_unsafe, records.size.to_u32, pointerof(count), flags) == 0
        raise IO::Error.from_winerror("ReadConsoleInputExW")
      end
      count.to_i32
    end
  end
{% end %}
