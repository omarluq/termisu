module Termisu::FFI
  def self.create(sync_updates : Bool) : UInt64
    context = Context.new(sync_updates)
    Registry.insert(context)
  end

  def self.destroy(handle : UInt64) : Status
    context = Registry.delete(handle)
    return invalid_handle_status unless context

    context.close
    Status::Ok
  end

  def self.close(handle : UInt64) : Status
    with_context(handle) do |context|
      context.close
      Status::Ok
    end
  end

  def self.size(handle : UInt64, out_size : ABI::Size*) : Status
    return invalid_argument_status("out_size is null") if out_size.null?

    with_context(handle) do |context|
      width, height = context.termisu.size
      size = out_size.value
      size.width = width
      size.height = height
      out_size.value = size
      Status::Ok
    end
  end

  def self.set_sync_updates(handle : UInt64, enabled : Bool) : Status
    with_context(handle) do |context|
      context.termisu.sync_updates = enabled
      Status::Ok
    end
  end

  def self.sync_updates?(handle : UInt64) : UInt8
    with_context_u8(handle) do |context|
      context.termisu.sync_updates? ? 1_u8 : 0_u8
    end
  end

  def self.clear(handle : UInt64) : Status
    with_context(handle) do |context|
      context.termisu.clear
      Status::Ok
    end
  end

  def self.render(handle : UInt64) : Status
    with_context(handle) do |context|
      context.termisu.render
      Status::Ok
    end
  end

  def self.sync(handle : UInt64) : Status
    with_context(handle) do |context|
      context.termisu.sync
      Status::Ok
    end
  end

  def self.set_cursor(handle : UInt64, x : Int32, y : Int32) : Status
    with_context(handle) do |context|
      context.termisu.set_cursor(x, y)
      Status::Ok
    end
  end

  def self.hide_cursor(handle : UInt64) : Status
    with_context(handle) do |context|
      context.termisu.hide_cursor
      Status::Ok
    end
  end

  def self.show_cursor(handle : UInt64) : Status
    with_context(handle) do |context|
      context.termisu.show_cursor
      Status::Ok
    end
  end

  def self.set_cell(handle : UInt64, x : Int32, y : Int32, codepoint : UInt32, style : ABI::CellStyle*) : Status
    with_context(handle) do |context|
      ch = Conversions.codepoint_to_char(codepoint)
      fg, bg, attr = Conversions.style_from_ptr(style)
      ok = context.termisu.set_cell(x, y, ch, fg: fg, bg: bg, attr: attr)
      if ok
        Status::Ok
      else
        ErrorState.set("set_cell rejected (out of bounds or unsupported codepoint)")
        Status::Rejected
      end
    end
  end

  def self.enable_timer_ms(handle : UInt64, interval_ms : Int32) : Status
    return invalid_argument_status("interval_ms must be > 0") if interval_ms <= 0

    with_context(handle) do |context|
      context.termisu.enable_timer(interval_ms.milliseconds)
      Status::Ok
    end
  end

  def self.enable_system_timer_ms(handle : UInt64, interval_ms : Int32) : Status
    return invalid_argument_status("interval_ms must be > 0") if interval_ms <= 0

    with_context(handle) do |context|
      context.termisu.enable_system_timer(interval_ms.milliseconds)
      Status::Ok
    end
  end

  def self.disable_timer(handle : UInt64) : Status
    with_context(handle) do |context|
      context.termisu.disable_timer
      Status::Ok
    end
  end

  def self.enable_mouse(handle : UInt64) : Status
    with_context(handle) do |context|
      context.termisu.enable_mouse
      Status::Ok
    end
  end

  def self.disable_mouse(handle : UInt64) : Status
    with_context(handle) do |context|
      context.termisu.disable_mouse
      Status::Ok
    end
  end

  def self.enable_enhanced_keyboard(handle : UInt64) : Status
    with_context(handle) do |context|
      context.termisu.enable_enhanced_keyboard
      Status::Ok
    end
  end

  def self.disable_enhanced_keyboard(handle : UInt64) : Status
    with_context(handle) do |context|
      context.termisu.disable_enhanced_keyboard
      Status::Ok
    end
  end

  def self.poll_event(handle : UInt64, timeout_ms : Int32, out_event : ABI::Event*) : Status
    return invalid_argument_status("out_event is null") if out_event.null?

    with_context(handle) do |context|
      event = if timeout_ms < 0
                context.termisu.poll_event
              else
                context.termisu.poll_event(timeout_ms)
              end

      if event
        out_event.value = Conversions.to_abi_event(event)
        Status::Ok
      else
        out_event.value = Conversions.blank_event
        Status::Timeout
      end
    end
  end

  def self.last_error_length : UInt64
    ErrorState.current.to_slice.size.to_u64
  end

  def self.copy_last_error(buffer : UInt8*, buffer_len : UInt64) : UInt64
    return 0_u64 if buffer.null? || buffer_len == 0_u64

    message = ErrorState.current
    bytes = message.to_slice
    writable = buffer_len - 1_u64
    max_copy = bytes.size.to_u64
    to_copy_u64 = writable < max_copy ? writable : max_copy
    to_copy = to_copy_u64.to_i

    if to_copy > 0
      buffer.copy_from(bytes.to_unsafe, to_copy)
    end

    buffer[to_copy] = 0_u8
    to_copy_u64
  end

  def self.clear_error_message : Nil
    ErrorState.clear
  end

  private def self.with_context(handle : UInt64, & : Context -> Status) : Status
    context = Registry.fetch(handle)
    return invalid_handle_status unless context
    yield context
  end

  private def self.with_context_u8(handle : UInt64, & : Context -> UInt8) : UInt8
    context = Registry.fetch(handle)
    unless context
      ErrorState.set("Invalid handle")
      return 0_u8
    end
    yield context
  end

  private def self.invalid_handle_status : Status
    ErrorState.set("Invalid handle")
    Status::InvalidHandle
  end

  private def self.invalid_argument_status(message : String) : Status
    ErrorState.set(message)
    Status::InvalidArgument
  end
end
