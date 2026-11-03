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

    def initialize(@fd : IO::FileDescriptor::Handle)
    end

    def buffered? : Bool
      @pending_pos < @pending.bytesize || @repeats > 0 || @record_pos < @record_count
    end

    def clear : Nil
      @record_pos = @record_count = @repeats = @pending_pos = 0
      @pending = ""
      @high_surrogate = nil
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
          decode_unit(@unit)
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
        next unless record.event_type == C::KEY_EVENT
        key = record.key_event
        next if key.key_down == 0
        next if key.unicode_char == 0 && !nul_key?(key)
        @unit = key.unicode_char
        @repeats = Math.max(key.repeat_count.to_i32, 1)
      end
      written
    end

    private def nul_key?(key : C::KeyEventRecord) : Bool
      # VT text records have no virtual key; Ctrl+Space and Unicode packets can be NUL.
      key.virtual_key_code == 0 || key.virtual_key_code == 0xE7 ||
        (key.virtual_key_code == 0x20 && (key.control_key_state & 0x000C) != 0)
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
