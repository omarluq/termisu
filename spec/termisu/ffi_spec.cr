require "../spec_helper"

private def termisu_error_message : String
  len = termisu_last_error_length
  return "" if len == 0_u64

  bytes = Bytes.new(len.to_i + 1, 0_u8)
  copied = termisu_last_error_copy(bytes.to_unsafe, bytes.size.to_u64)
  copied.should be <= len
  String.new(bytes.to_unsafe)
end

private def default_ffi_style : Termisu::FFI::ABI::CellStyle
  style = uninitialized Termisu::FFI::ABI::CellStyle
  style.fg.mode = Termisu::FFI::ColorMode::Default.value
  style.fg.index = -1
  style.fg.r = 0_u8
  style.fg.g = 0_u8
  style.fg.b = 0_u8
  style.bg = style.fg
  style.attr = 0_u16
  style
end

private def ffi_cell_op(x : Int32, y : Int32, codepoint : Int32) : Termisu::FFI::ABI::CellOp
  op = uninitialized Termisu::FFI::ABI::CellOp
  op.x = x
  op.y = y
  op.codepoint = codepoint
  op.style = default_ffi_style
  op
end

describe "Termisu C ABI" do
  it "exposes the expected ABI version" do
    termisu_abi_version.should eq(1_u32)
  end

  it "exposes a stable non-zero layout signature" do
    signature = termisu_layout_signature
    signature.should eq(Termisu::FFI::Layout.signature)
    signature.should_not eq(0_u64)
  end

  it "returns invalid handle status and populates last error" do
    termisu_clear_error
    termisu_destroy(0_u64).should eq(Termisu::FFI::Status::InvalidHandle.value)
    termisu_error_message.should contain("Invalid handle")
  end

  it "clears last error state explicitly" do
    termisu_destroy(0_u64).should eq(Termisu::FFI::Status::InvalidHandle.value)
    termisu_last_error_length.should be > 0_u64

    termisu_clear_error
    termisu_last_error_length.should eq(0_u64)
  end

  it "returns 0 when copying last error into a null buffer" do
    termisu_destroy(0_u64).should eq(Termisu::FFI::Status::InvalidHandle.value)
    termisu_last_error_length.should be > 0_u64
    termisu_last_error_copy(Pointer(UInt8).null, 16_u64).should eq(0_u64)
  end

  it "rejects null event pointer in poll_event" do
    termisu_clear_error
    status = termisu_poll_event(0_u64, 0, Pointer(Termisu::FFI::ABI::Event).null)
    status.should eq(Termisu::FFI::Status::InvalidArgument.value)
    termisu_error_message.should contain("out_event is null")
  end

  it "rejects invalid handle for set_cell" do
    style = default_ffi_style
    status = termisu_set_cell(9999_u64, 0, 0, 'A'.ord.to_u32, pointerof(style))
    status.should eq(Termisu::FFI::Status::InvalidHandle.value)
    termisu_error_message.should contain("Invalid handle")
  end

  it "rejects invalid handle for set_cells" do
    op = ffi_cell_op(0, 0, 'A'.ord)
    status = termisu_set_cells(9999_u64, pointerof(op), 1_u64)
    status.should eq(Termisu::FFI::Status::InvalidHandle.value)
    termisu_error_message.should contain("Invalid handle")
  end

  it "rejects null ops pointer in set_cells when count is positive" do
    termisu_clear_error
    status = termisu_set_cells(0_u64, Pointer(Termisu::FFI::ABI::CellOp).null, 1_u64)
    status.should eq(Termisu::FFI::Status::InvalidArgument.value)
    termisu_error_message.should contain("ops is null")
  end

  it "still validates the handle for an empty set_cells batch" do
    termisu_clear_error
    status = termisu_set_cells(0_u64, Pointer(Termisu::FFI::ABI::CellOp).null, 0_u64)
    status.should eq(Termisu::FFI::Status::InvalidHandle.value)
    termisu_error_message.should contain("Invalid handle")
  end

  it "supports core operations on a valid handle" do
    termisu_clear_error
    handle = termisu_create(1_u8)
    handle.should_not eq(0_u64)

    begin
      size = uninitialized Termisu::FFI::ABI::Size
      termisu_size(handle, pointerof(size)).should eq(Termisu::FFI::Status::Ok.value)
      size.width.should be >= 0
      size.height.should be >= 0

      termisu_sync_updates(handle).should eq(1_u8)
      termisu_set_sync_updates(handle, 0_u8).should eq(Termisu::FFI::Status::Ok.value)
      termisu_sync_updates(handle).should eq(0_u8)
      termisu_set_sync_updates(handle, 1_u8).should eq(Termisu::FFI::Status::Ok.value)
      termisu_sync_updates(handle).should eq(1_u8)

      termisu_clear(handle).should eq(Termisu::FFI::Status::Ok.value)
      termisu_render(handle).should eq(Termisu::FFI::Status::Ok.value)
      termisu_sync(handle).should eq(Termisu::FFI::Status::Ok.value)
      termisu_set_cursor(handle, 0, 0).should eq(Termisu::FFI::Status::Ok.value)
      termisu_hide_cursor(handle).should eq(Termisu::FFI::Status::Ok.value)
      termisu_show_cursor(handle).should eq(Termisu::FFI::Status::Ok.value)

      style = default_ffi_style
      in_bounds_status = termisu_set_cell(handle, 0, 0, 'A'.ord.to_u32, pointerof(style))
      if size.width > 0 && size.height > 0
        in_bounds_status.should eq(Termisu::FFI::Status::Ok.value)
      else
        in_bounds_status.should eq(Termisu::FFI::Status::Rejected.value)
        termisu_error_message.should contain("set_cell rejected")
      end

      rejected = termisu_set_cell(handle, size.width, 0, 'A'.ord.to_u32, pointerof(style))
      rejected.should eq(Termisu::FFI::Status::Rejected.value)
      termisu_error_message.should contain("set_cell rejected")

      if size.width > 0 && size.height > 0
        invalid_codepoint = termisu_set_cell(handle, 0, 0, 0x11_0000_u32, pointerof(style))
        invalid_codepoint.should eq(Termisu::FFI::Status::Error.value)
        termisu_error_message.should contain("Invalid Unicode codepoint")
      end

      ops = StaticArray[
        ffi_cell_op(0, 0, 'B'.ord),
        ffi_cell_op(1, 0, 'C'.ord),
      ]
      batch_status = termisu_set_cells(handle, ops.to_unsafe, ops.size.to_u64)
      if size.width > 1 && size.height > 0
        batch_status.should eq(Termisu::FFI::Status::Ok.value)
      else
        batch_status.should eq(Termisu::FFI::Status::Rejected.value)
        termisu_error_message.should contain("set_cells rejected")
      end

      mixed = StaticArray[
        ffi_cell_op(0, 0, 'D'.ord),
        ffi_cell_op(size.width, 0, 'E'.ord),
      ]
      mixed_status = termisu_set_cells(handle, mixed.to_unsafe, mixed.size.to_u64)
      mixed_status.should eq(Termisu::FFI::Status::Rejected.value)
      termisu_error_message.should contain("set_cells rejected")

      empty_status = termisu_set_cells(handle, Pointer(Termisu::FFI::ABI::CellOp).null, 0_u64)
      empty_status.should eq(Termisu::FFI::Status::Ok.value)

      # Codepoint validation raises before any bounds check, so these hold
      # regardless of the reported terminal size.
      bad = StaticArray[
        ffi_cell_op(0, 0, 'F'.ord),
        ffi_cell_op(0, 0, 0x11_0000),
      ]
      bad_status = termisu_set_cells(handle, bad.to_unsafe, bad.size.to_u64)
      bad_status.should eq(Termisu::FFI::Status::Error.value)
      termisu_error_message.should contain("Invalid Unicode codepoint")

      negative = StaticArray[ffi_cell_op(0, 0, -1)]
      negative_status = termisu_set_cells(handle, negative.to_unsafe, 1_u64)
      negative_status.should eq(Termisu::FFI::Status::Error.value)
      termisu_error_message.should contain("Invalid Unicode codepoint")

      termisu_enable_timer_ms(handle, 16).should eq(Termisu::FFI::Status::Ok.value)
      termisu_disable_timer(handle).should eq(Termisu::FFI::Status::Ok.value)
      termisu_enable_system_timer_ms(handle, 16).should eq(Termisu::FFI::Status::Ok.value)
      termisu_disable_timer(handle).should eq(Termisu::FFI::Status::Ok.value)

      termisu_enable_mouse(handle).should eq(Termisu::FFI::Status::Ok.value)
      termisu_disable_mouse(handle).should eq(Termisu::FFI::Status::Ok.value)
      termisu_enable_enhanced_keyboard(handle).should eq(Termisu::FFI::Status::Ok.value)
      termisu_disable_enhanced_keyboard(handle).should eq(Termisu::FFI::Status::Ok.value)

      event = uninitialized Termisu::FFI::ABI::Event
      poll_status = termisu_poll_event(handle, 0, pointerof(event))
      valid_poll = [Termisu::FFI::Status::Ok.value, Termisu::FFI::Status::Timeout.value]
      valid_poll.should contain(poll_status)
    ensure
      termisu_destroy(handle)
    end
  end

  it "validates timer interval arguments" do
    handle = termisu_create(1_u8)
    handle.should_not eq(0_u64)

    begin
      termisu_enable_timer_ms(handle, 0).should eq(Termisu::FFI::Status::InvalidArgument.value)
      termisu_error_message.should contain("interval_ms must be > 0")

      termisu_enable_system_timer_ms(handle, -1).should eq(Termisu::FFI::Status::InvalidArgument.value)
      termisu_error_message.should contain("interval_ms must be > 0")
    ensure
      termisu_destroy(handle)
    end
  end

  it "closes and destroys handles idempotently" do
    handle = termisu_create(1_u8)
    handle.should_not eq(0_u64)

    termisu_close(handle).should eq(Termisu::FFI::Status::Ok.value)
    termisu_destroy(handle).should eq(Termisu::FFI::Status::Ok.value)
    termisu_destroy(handle).should eq(Termisu::FFI::Status::InvalidHandle.value)
  end

  it "truncates copied error messages safely" do
    termisu_clear_error
    termisu_destroy(0_u64).should eq(Termisu::FFI::Status::InvalidHandle.value)

    buffer = Bytes.new(4, 0_u8)
    copied = termisu_last_error_copy(buffer.to_unsafe, buffer.size.to_u64)
    copied.should eq(3_u64)
    String.new(buffer.to_unsafe).size.should be <= 3

    single = Bytes.new(1, 7_u8)
    termisu_last_error_copy(single.to_unsafe, 1_u64).should eq(0_u64)
    single[0].should eq(0_u8)
  end

  it "handles very large buffer lengths without overflow" do
    termisu_clear_error
    termisu_destroy(0_u64).should eq(Termisu::FFI::Status::InvalidHandle.value)

    len = termisu_last_error_length
    len.should be > 0_u64

    bytes = Bytes.new(len.to_i + 1, 0_u8)
    copied = termisu_last_error_copy(bytes.to_unsafe, UInt64::MAX)
    copied.should eq(len)
    String.new(bytes.to_unsafe).should contain("Invalid handle")
  end
end
