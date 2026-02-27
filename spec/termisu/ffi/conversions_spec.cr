require "../../spec_helper"

private def abi_color(
  mode : UInt8,
  index : Int32 = -1,
  r : UInt8 = 0_u8,
  g : UInt8 = 0_u8,
  b : UInt8 = 0_u8,
) : Termisu::FFI::ABI::Color
  color = uninitialized Termisu::FFI::ABI::Color
  color.mode = mode
  color.index = index
  color.r = r
  color.g = g
  color.b = b
  color
end

describe Termisu::FFI::Conversions do
  it "converts valid and invalid Unicode codepoints" do
    Termisu::FFI::Conversions.codepoint_to_char('A'.ord.to_u32).should eq('A')
    expect_raises(ArgumentError, /Invalid Unicode codepoint/) do
      Termisu::FFI::Conversions.codepoint_to_char(0x11_0000_u32)
    end
  end

  it "maps ABI style pointers into Termisu style defaults and explicit colors" do
    fg = abi_color(Termisu::FFI::ColorMode::Rgb.value, r: 10_u8, g: 20_u8, b: 30_u8)
    bg = abi_color(Termisu::FFI::ColorMode::Ansi256.value, index: 201)

    style = uninitialized Termisu::FFI::ABI::CellStyle
    style.fg = fg
    style.bg = bg
    style.attr = (Termisu::Attribute::Bold.value | Termisu::Attribute::Underline.value).to_u16

    null_fg, null_bg, null_attr = Termisu::FFI::Conversions.style_from_ptr(Pointer(Termisu::FFI::ABI::CellStyle).null)
    null_fg.should eq(Termisu::Color.white)
    null_bg.should eq(Termisu::Color.default)
    null_attr.should eq(Termisu::Attribute::None)

    mapped_fg, mapped_bg, mapped_attr = Termisu::FFI::Conversions.style_from_ptr(pointerof(style))
    mapped_fg.should eq(Termisu::Color.rgb(10_u8, 20_u8, 30_u8))
    mapped_bg.should eq(Termisu::Color.ansi256(201))
    mapped_attr.should eq(Termisu::Attribute::Bold | Termisu::Attribute::Underline)
  end

  it "validates unknown color modes and attribute bits" do
    unknown = abi_color(255_u8, index: 0)
    expect_raises(ArgumentError, /Unknown color mode/) do
      Termisu::FFI::Conversions.color_from_abi(unknown)
    end

    expect_raises(ArgumentError, /Unknown attribute bits/) do
      Termisu::FFI::Conversions.attr_from_bits(0x8000_u16)
    end
  end

  it "builds ABI events for each event type" do
    key = Termisu::Event::Key.new(Termisu::Input::Key::LowerA, Termisu::Input::Modifier::Ctrl)
    key_out = Termisu::FFI::Conversions.to_abi_event(key)
    key_out.event_type.should eq(Termisu::FFI::EventType::Key.value)
    key_out.modifiers.should eq(Termisu::Input::Modifier::Ctrl.value.to_u8)
    key_out.key_code.should eq(Termisu::Input::Key::LowerA.value)
    key_out.key_char.should eq('a'.ord)

    mouse = Termisu::Event::Mouse.new(7, 9, Termisu::Event::Mouse::Button::Right, Termisu::Input::Modifier::Shift, true)
    mouse_out = Termisu::FFI::Conversions.to_abi_event(mouse)
    mouse_out.event_type.should eq(Termisu::FFI::EventType::Mouse.value)
    mouse_out.mouse_x.should eq(7)
    mouse_out.mouse_y.should eq(9)
    mouse_out.mouse_button.should eq(Termisu::Event::Mouse::Button::Right.value)
    mouse_out.mouse_motion.should eq(1_u8)

    resize = Termisu::Event::Resize.new(120, 40, 80, 24)
    resize_out = Termisu::FFI::Conversions.to_abi_event(resize)
    resize_out.event_type.should eq(Termisu::FFI::EventType::Resize.value)
    resize_out.resize_width.should eq(120)
    resize_out.resize_height.should eq(40)
    resize_out.resize_old_width.should eq(80)
    resize_out.resize_old_height.should eq(24)
    resize_out.resize_has_old.should eq(1_u8)

    partial_resize = Termisu::Event::Resize.new(100, 30, 80, nil)
    partial_out = Termisu::FFI::Conversions.to_abi_event(partial_resize)
    partial_out.resize_has_old.should eq(0_u8)
    partial_out.resize_old_width.should eq(0)
    partial_out.resize_old_height.should eq(0)

    tick = Termisu::Event::Tick.new(100.milliseconds, 16.milliseconds, 9_u64, 2_u64)
    tick_out = Termisu::FFI::Conversions.to_abi_event(tick)
    tick_out.event_type.should eq(Termisu::FFI::EventType::Tick.value)
    tick_out.tick_frame.should eq(9_u64)
    tick_out.tick_elapsed_ns.should eq(100.milliseconds.total_nanoseconds.to_i64)
    tick_out.tick_delta_ns.should eq(16.milliseconds.total_nanoseconds.to_i64)
    tick_out.tick_missed_ticks.should eq(2_u64)

    mode = Termisu::Event::ModeChange.new(Termisu::Terminal::Mode::Canonical, Termisu::Terminal::Mode::None)
    mode_out = Termisu::FFI::Conversions.to_abi_event(mode)
    mode_out.event_type.should eq(Termisu::FFI::EventType::ModeChange.value)
    mode_out.mode_current.should eq(Termisu::Terminal::Mode::Canonical.value.to_u32)
    mode_out.mode_previous.should eq(Termisu::Terminal::Mode::None.value.to_u32)
    mode_out.mode_has_previous.should eq(1_u8)
  end

  it "emits blank ABI events with defaults" do
    blank = Termisu::FFI::Conversions.blank_event
    blank.event_type.should eq(Termisu::FFI::EventType::None.value)
    blank.key_char.should eq(-1)
    blank.modifiers.should eq(0_u8)
  end
end
