require "../console"

{% if flag?(:win32) %}
  # Reader-local UTF-16/VT stream state. Only the input owner calls read.
  class Termisu::System::Console::Input
    getter fd : IO::FileDescriptor::Handle

    @records = Slice(C::InputRecord).new(32) { C::InputRecord.new }
    @record_pos = 0
    @record_count = 0
    @unit = 0_u16
    @repeats = 0
    @pending = ""
    @pending_pos = 0
    @high_surrogate : UInt16?
    @mouse_buttons = 0_u32
    @mouse_sequence : String?
    @wheel_delta = 0
    @horizontal_wheel_delta = 0

    def initialize(@fd : IO::FileDescriptor::Handle, @output_fd : IO::FileDescriptor::Handle? = nil)
    end

    def buffered? : Bool
      @pending_pos < @pending.bytesize || @repeats > 0 || @record_pos < @record_count
    end

    def clear : Nil
      @record_pos = @record_count = @repeats = @pending_pos = 0
      @pending = ""
      @high_surrogate = nil
      @mouse_buttons = 0_u32
      @mouse_sequence = nil
      @wheel_delta = @horizontal_wheel_delta = 0
    end

    # At most one new native batch per call; repeat counts never expand into a FIFO.
    def read(buffer : Bytes) : Int32
      written = 0
      fetched = false
      while written < buffer.size
        if @pending_pos < @pending.bytesize
          count = Math.min(buffer.size - written, @pending.bytesize - @pending_pos)
          buffer[written, count].copy_from(@pending.to_slice[@pending_pos, count])
          @pending_pos += count
          written += count
          next
        end
        if @repeats > 0
          @repeats -= 1
          if sequence = @mouse_sequence
            @pending, @pending_pos = sequence, 0
          else
            decode_unit(@unit)
          end
          next
        end
        if @record_pos >= @record_count
          break if fetched
          @record_count = Console.read_records(LibC::HANDLE.new(@fd), @records)
          @record_pos = 0
          fetched = true
          break if @record_count == 0
        end
        record = @records[@record_pos]
        @record_pos += 1
        if record.event_type == C::MOUSE_EVENT
          # Both SDK union members have the same size and DWORD alignment.
          decode_mouse(record.key_event.unsafe_as(C::MouseEventRecord))
          next
        end
        next unless record.event_type == C::KEY_EVENT
        key = record.key_event
        next if key.key_down == 0
        next if key.unicode_char == 0 && !nul_key?(key)
        @mouse_sequence = nil
        @unit = key.unicode_char
        @repeats = Math.max(key.repeat_count.to_i32, 1)
      end
      written
    end

    private MOUSE_BUTTONS = { {1_u32, 0}, {4_u32, 1}, {2_u32, 2}, {8_u32, 128}, {16_u32, 129} }

    private def decode_mouse(mouse : C::MouseEventRecord) : Nil
      x, y = mouse_position(mouse.position)
      buttons = mouse.button_state & 0x001F_u32
      previous, @mouse_buttons = @mouse_buttons, buttons
      return if x < 1 || y < 1
      modifiers = mouse_modifiers(mouse.control_key_state)
      @repeats = 1
      @mouse_sequence = String.build do |output|
        flags = mouse.event_flags
        if (flags & (C::MOUSE_WHEELED | C::MOUSE_HWHEELED)) != 0
          if button = wheel_button(mouse)
            sgr_mouse(output, button | modifiers, x, y)
          end
        elsif (flags & C::MOUSE_MOVED) != 0
          button = MOUSE_BUTTONS.find { |mask, _| (buttons & mask) != 0 }.try(&.[1]) || 3
          sgr_mouse(output, button | modifiers | 32, x, y)
        else
          MOUSE_BUTTONS.each do |mask, button|
            pressed = (buttons & mask) != 0
            next if ((previous ^ buttons) & mask) == 0 && !((flags & C::DOUBLE_CLICK) != 0 && pressed)
            sgr_mouse(output, button | modifiers, x, y, release: !pressed)
          end
        end
      end
    end

    private def wheel_button(mouse : C::MouseEventRecord) : Int32?
      delta = (mouse.button_state >> 16).to_u16.unsafe_as(Int16).to_i32
      horizontal = (mouse.event_flags & C::MOUSE_HWHEELED) != 0
      if horizontal
        @horizontal_wheel_delta += delta
        steps = @horizontal_wheel_delta.tdiv(120)
        @horizontal_wheel_delta = @horizontal_wheel_delta.remainder(120)
      else
        @wheel_delta += delta
        steps = @wheel_delta.tdiv(120)
        @wheel_delta = @wheel_delta.remainder(120)
      end
      return if steps == 0
      @repeats = steps.abs
      horizontal ? (steps > 0 ? 67 : 66) : (steps > 0 ? 64 : 65)
    end

    private def mouse_position(position : C::Coord) : {Int32, Int32}
      x, y = position.x.to_i32 + 1, position.y.to_i32 + 1
      if fd = @output_fd
        if C.GetConsoleScreenBufferInfo(LibC::HANDLE.new(fd), out info) == 0
          raise IO::Error.from_winerror("GetConsoleScreenBufferInfo(mouse input)")
        end
        x -= info.window.left
        y -= info.window.top
      end
      {x, y}
    end

    private def mouse_modifiers(state : UInt32) : Int32
      modifiers = (state & 0x0010) != 0 ? 4 : 0
      modifiers |= 8 if (state & 0x0003) != 0
      modifiers |= 16 if (state & 0x000C) != 0
      modifiers
    end

    private def sgr_mouse(output : IO, button : Int32, x : Int32, y : Int32, *, release : Bool = false) : Nil
      output << "\e[<" << button << ';' << x << ';' << y << (release ? 'm' : 'M')
    end

    private def nul_key?(key : C::KeyEventRecord) : Bool
      return true if key.virtual_key_code == 0 || key.virtual_key_code == 0xE7 ||
                     (key.virtual_key_code == 0x20 && (key.control_key_state & 0x000C) != 0)
      # Conhost remaps NUL with VkKeyScanW(0), not necessarily Ctrl+Space.
      mapping = Keyboard.VkKeyScanW(0_u16)
      state = key.control_key_state
      key.virtual_key_code == (mapping & 0xFF) &&
        ((state & 0x0010) != 0) == ((mapping & 0x0100) != 0) &&
        ((state & 0x000C) != 0) == ((mapping & 0x0200) != 0) &&
        ((state & 0x0003) != 0) == ((mapping & 0x0400) != 0)
    end

    private def decode_unit(unit : UInt16) : Nil
      @pending_pos = 0
      prefix = ""
      if high = @high_surrogate
        @high_surrogate = nil
        if 0xDC00 <= unit <= 0xDFFF
          scalar = 0x10000 + ((high.to_i32 - 0xD800) << 10) + unit.to_i32 - 0xDC00
          @pending = scalar.chr.to_s
          return
        end
        prefix = "\uFFFD"
      end
      if 0xD800 <= unit <= 0xDBFF
        @high_surrogate = unit
        @pending = prefix
      elsif 0xDC00 <= unit <= 0xDFFF
        @pending = prefix + "\uFFFD"
      else
        @pending = prefix + unit.chr.to_s
      end
    end
  end
{% end %}
