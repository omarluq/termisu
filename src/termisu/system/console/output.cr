require "../console"

{% if flag?(:win32) %}
  # A bounded UTF-8 sink over a borrowed console handle; never changes code pages.
  class Termisu::System::Console::Output
    CAPACITY = 8192

    @buffer = IO::Memory.new(CAPACITY)

    def initialize(@fd : IO::FileDescriptor::Handle)
    end

    def write(data : Bytes) : Nil
      offset = 0
      while offset < data.size
        count = Math.min(data.size - offset, CAPACITY - @buffer.size)
        @buffer.write(data[offset, count])
        offset += count
        flush if @buffer.size == CAPACITY
      end
    end

    def flush : Nil
      bytes = @buffer.to_slice
      return if bytes.empty?
      length = complete_prefix(bytes)
      return if length == 0
      text = String.new(bytes[0, length])
      raise IO::Error.new("Invalid UTF-8 console output") unless text.valid_encoding?
      write_console(text.to_utf16)
      tail = bytes[length, bytes.size - length].dup
      @buffer.clear
      @buffer.write(tail)
    rescue error
      # Failed frames must not leave stale bytes queued for the next full render.
      @buffer.clear
      raise error
    end

    def finish : Nil
      flush
      raise IO::Error.new("Incomplete UTF-8 console output") unless @buffer.empty?
    end

    private def write_console(wide : Slice(UInt16)) : Nil
      handle = LibC::HANDLE.new(@fd)
      if LibC.GetConsoleMode(handle, out original) == 0
        raise IO::Error.from_winerror("GetConsoleMode(console output)")
      end
      enabled = original | 0x000D_u32
      changed = false
      error : Exception? = nil
      begin
        if enabled != original
          if LibC.SetConsoleMode(handle, enabled) == 0
            raise IO::Error.from_winerror("SetConsoleMode(VT output)")
          end
          changed = true
        end
        write_wide(handle, wide)
      rescue ex
        error = ex
      ensure
        if changed && LibC.SetConsoleMode(handle, original) == 0
          error ||= IO::Error.from_winerror("SetConsoleMode(restore output)")
        end
      end
      raise error if error
    end

    private def write_wide(handle : LibC::HANDLE, wide : Slice(UInt16)) : Nil
      offset = 0
      while offset < wide.size
        remaining = wide.size - offset
        if C.WriteConsoleW(handle, wide.to_unsafe + offset, remaining.to_u32, out written, nil) == 0
          raise IO::Error.from_winerror("WriteConsoleW")
        end
        if written == 0 || written > remaining
          raise IO::Error.new("WriteConsoleW made invalid progress")
        end
        offset += written.to_i32
      end
    end

    private def complete_prefix(bytes : Bytes) : Int32
      lead = bytes.size - 1
      while lead > 0 && (bytes[lead] & 0xC0) == 0x80
        lead -= 1
      end
      width = case bytes[lead]
              when 0xC2..0xDF then 2
              when 0xE0..0xEF then 3
              when 0xF0..0xF4 then 4
              else                 1
              end
      bytes.size - lead < width ? lead : bytes.size
    end
  end
{% end %}
