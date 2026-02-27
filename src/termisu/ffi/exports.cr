# Exported C symbols.

fun termisu_abi_version : UInt32
  Termisu::FFI::ABI_VERSION
end

fun termisu_layout_signature : UInt64
  Termisu::FFI::Runtime.ensure_initialized
  Termisu::FFI::Layout.signature
end

fun termisu_create(sync_updates : UInt8) : UInt64
  Termisu::FFI::Guards.safe_handle { Termisu::FFI.create(sync_updates != 0_u8) }
end

fun termisu_destroy(handle : UInt64) : Int32
  Termisu::FFI::Guards.safe_status { Termisu::FFI.destroy(handle) }
end

fun termisu_close(handle : UInt64) : Int32
  Termisu::FFI::Guards.safe_status { Termisu::FFI.close(handle) }
end

fun termisu_size(handle : UInt64, out_size : Termisu::FFI::ABI::Size*) : Int32
  Termisu::FFI::Guards.safe_status { Termisu::FFI.size(handle, out_size) }
end

fun termisu_set_sync_updates(handle : UInt64, enabled : UInt8) : Int32
  Termisu::FFI::Guards.safe_status { Termisu::FFI.set_sync_updates(handle, enabled != 0_u8) }
end

fun termisu_sync_updates(handle : UInt64) : UInt8
  Termisu::FFI::Guards.safe_u8 { Termisu::FFI.sync_updates?(handle) }
end

fun termisu_clear(handle : UInt64) : Int32
  Termisu::FFI::Guards.safe_status { Termisu::FFI.clear(handle) }
end

fun termisu_render(handle : UInt64) : Int32
  Termisu::FFI::Guards.safe_status { Termisu::FFI.render(handle) }
end

fun termisu_sync(handle : UInt64) : Int32
  Termisu::FFI::Guards.safe_status { Termisu::FFI.sync(handle) }
end

fun termisu_set_cursor(handle : UInt64, x : Int32, y : Int32) : Int32
  Termisu::FFI::Guards.safe_status { Termisu::FFI.set_cursor(handle, x, y) }
end

fun termisu_hide_cursor(handle : UInt64) : Int32
  Termisu::FFI::Guards.safe_status { Termisu::FFI.hide_cursor(handle) }
end

fun termisu_show_cursor(handle : UInt64) : Int32
  Termisu::FFI::Guards.safe_status { Termisu::FFI.show_cursor(handle) }
end

fun termisu_set_cell(
  handle : UInt64,
  x : Int32,
  y : Int32,
  codepoint : UInt32,
  style : Termisu::FFI::ABI::CellStyle*,
) : Int32
  Termisu::FFI::Guards.safe_status { Termisu::FFI.set_cell(handle, x, y, codepoint, style) }
end

fun termisu_enable_timer_ms(handle : UInt64, interval_ms : Int32) : Int32
  Termisu::FFI::Guards.safe_status { Termisu::FFI.enable_timer_ms(handle, interval_ms) }
end

fun termisu_enable_system_timer_ms(handle : UInt64, interval_ms : Int32) : Int32
  Termisu::FFI::Guards.safe_status { Termisu::FFI.enable_system_timer_ms(handle, interval_ms) }
end

fun termisu_disable_timer(handle : UInt64) : Int32
  Termisu::FFI::Guards.safe_status { Termisu::FFI.disable_timer(handle) }
end

fun termisu_enable_mouse(handle : UInt64) : Int32
  Termisu::FFI::Guards.safe_status { Termisu::FFI.enable_mouse(handle) }
end

fun termisu_disable_mouse(handle : UInt64) : Int32
  Termisu::FFI::Guards.safe_status { Termisu::FFI.disable_mouse(handle) }
end

fun termisu_enable_enhanced_keyboard(handle : UInt64) : Int32
  Termisu::FFI::Guards.safe_status { Termisu::FFI.enable_enhanced_keyboard(handle) }
end

fun termisu_disable_enhanced_keyboard(handle : UInt64) : Int32
  Termisu::FFI::Guards.safe_status { Termisu::FFI.disable_enhanced_keyboard(handle) }
end

fun termisu_poll_event(
  handle : UInt64,
  timeout_ms : Int32,
  out_event : Termisu::FFI::ABI::Event*,
) : Int32
  Termisu::FFI::Guards.safe_status { Termisu::FFI.poll_event(handle, timeout_ms, out_event) }
end

fun termisu_last_error_length : UInt64
  Termisu::FFI::Runtime.ensure_initialized
  Termisu::FFI.last_error_length
end

fun termisu_last_error_copy(buffer : UInt8*, buffer_len : UInt64) : UInt64
  Termisu::FFI::Runtime.ensure_initialized
  Termisu::FFI.copy_last_error(buffer, buffer_len)
end

fun termisu_clear_error : Nil
  Termisu::FFI::Runtime.ensure_initialized
  Termisu::FFI.clear_error_message
end
