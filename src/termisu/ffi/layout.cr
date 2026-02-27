module Termisu::FFI::Layout
  FNV_OFFSET_BASIS = 0xcbf29ce484222325_u64
  FNV_PRIME        =      0x100000001b3_u64

  VALUES = {
    sizeof(Termisu::FFI::ABI::Color).to_u64,
    offsetof(Termisu::FFI::ABI::Color, @mode).to_u64,
    offsetof(Termisu::FFI::ABI::Color, @index).to_u64,
    offsetof(Termisu::FFI::ABI::Color, @r).to_u64,
    offsetof(Termisu::FFI::ABI::Color, @g).to_u64,
    offsetof(Termisu::FFI::ABI::Color, @b).to_u64,

    sizeof(Termisu::FFI::ABI::CellStyle).to_u64,
    offsetof(Termisu::FFI::ABI::CellStyle, @fg).to_u64,
    offsetof(Termisu::FFI::ABI::CellStyle, @bg).to_u64,
    offsetof(Termisu::FFI::ABI::CellStyle, @attr).to_u64,

    sizeof(Termisu::FFI::ABI::Size).to_u64,
    offsetof(Termisu::FFI::ABI::Size, @width).to_u64,
    offsetof(Termisu::FFI::ABI::Size, @height).to_u64,

    sizeof(Termisu::FFI::ABI::Event).to_u64,
    offsetof(Termisu::FFI::ABI::Event, @event_type).to_u64,
    offsetof(Termisu::FFI::ABI::Event, @modifiers).to_u64,
    offsetof(Termisu::FFI::ABI::Event, @key_code).to_u64,
    offsetof(Termisu::FFI::ABI::Event, @key_char).to_u64,
    offsetof(Termisu::FFI::ABI::Event, @mouse_x).to_u64,
    offsetof(Termisu::FFI::ABI::Event, @mouse_y).to_u64,
    offsetof(Termisu::FFI::ABI::Event, @mouse_button).to_u64,
    offsetof(Termisu::FFI::ABI::Event, @mouse_motion).to_u64,
    offsetof(Termisu::FFI::ABI::Event, @resize_width).to_u64,
    offsetof(Termisu::FFI::ABI::Event, @resize_height).to_u64,
    offsetof(Termisu::FFI::ABI::Event, @resize_old_width).to_u64,
    offsetof(Termisu::FFI::ABI::Event, @resize_old_height).to_u64,
    offsetof(Termisu::FFI::ABI::Event, @resize_has_old).to_u64,
    offsetof(Termisu::FFI::ABI::Event, @tick_frame).to_u64,
    offsetof(Termisu::FFI::ABI::Event, @tick_elapsed_ns).to_u64,
    offsetof(Termisu::FFI::ABI::Event, @tick_delta_ns).to_u64,
    offsetof(Termisu::FFI::ABI::Event, @tick_missed_ticks).to_u64,
    offsetof(Termisu::FFI::ABI::Event, @mode_current).to_u64,
    offsetof(Termisu::FFI::ABI::Event, @mode_previous).to_u64,
    offsetof(Termisu::FFI::ABI::Event, @mode_has_previous).to_u64,
  }

  def self.signature : UInt64
    hash = FNV_OFFSET_BASIS
    VALUES.each do |value|
      hash = (hash ^ value) &* FNV_PRIME
    end
    hash
  end
end
