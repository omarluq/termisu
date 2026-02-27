require "../spec_helper"

private def termisu_error_message : String
  len = termisu_last_error_length
  return "" if len == 0_u64

  bytes = Bytes.new(len.to_i + 1, 0_u8)
  copied = termisu_last_error_copy(bytes.to_unsafe, bytes.size.to_u64)
  copied.should be <= len
  String.new(bytes.to_unsafe)
end

describe "Termisu C ABI" do
  it "exposes the expected ABI version" do
    termisu_abi_version.should eq(1_u32)
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
    style = uninitialized Termisu::FFI::ABI::CellStyle
    style.fg.mode = Termisu::FFI::ColorMode::Default.value
    style.fg.index = -1
    style.fg.r = 0_u8
    style.fg.g = 0_u8
    style.fg.b = 0_u8
    style.bg = style.fg
    style.attr = 0_u16

    status = termisu_set_cell(9999_u64, 0, 0, 'A'.ord.to_u32, pointerof(style))
    status.should eq(Termisu::FFI::Status::InvalidHandle.value)
    termisu_error_message.should contain("Invalid handle")
  end
end
