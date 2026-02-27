module Termisu::FFI::Conversions
  ATTRIBUTE_MASK =
    (Attribute::Bold.value |
      Attribute::Underline.value |
      Attribute::Reverse.value |
      Attribute::Blink.value |
      Attribute::Dim.value |
      Attribute::Cursive.value |
      Attribute::Hidden.value |
      Attribute::Strikethrough.value).to_u16

  def self.codepoint_to_char(codepoint : UInt32) : Char
    codepoint.chr
  rescue ex
    raise ArgumentError.new("Invalid Unicode codepoint #{codepoint}: #{ex.message || ex.class.name}")
  end

  def self.style_from_ptr(style : Termisu::FFI::ABI::CellStyle*) : {Color, Color, Attribute}
    return {Color.white, Color.default, Attribute::None} if style.null?

    style_value = style.value
    fg = color_from_abi(style_value.fg)
    bg = color_from_abi(style_value.bg)
    attr = attr_from_bits(style_value.attr)
    {fg, bg, attr}
  end

  def self.color_from_abi(color : Termisu::FFI::ABI::Color) : Color
    case color.mode
    when Termisu::FFI::ColorMode::Default.value
      Color.default
    when Termisu::FFI::ColorMode::Ansi8.value
      Color.ansi8(color.index)
    when Termisu::FFI::ColorMode::Ansi256.value
      Color.ansi256(color.index)
    when Termisu::FFI::ColorMode::Rgb.value
      Color.rgb(color.r, color.g, color.b)
    else
      raise ArgumentError.new("Unknown color mode #{color.mode}")
    end
  end

  def self.attr_from_bits(bits : UInt16) : Attribute
    invalid_bits = bits & ~ATTRIBUTE_MASK
    raise ArgumentError.new("Unknown attribute bits 0x#{bits.to_s(16)}") if invalid_bits != 0

    attr = Attribute::None
    attr |= Attribute::Bold if (bits & Attribute::Bold.value) != 0
    attr |= Attribute::Underline if (bits & Attribute::Underline.value) != 0
    attr |= Attribute::Reverse if (bits & Attribute::Reverse.value) != 0
    attr |= Attribute::Blink if (bits & Attribute::Blink.value) != 0
    attr |= Attribute::Dim if (bits & Attribute::Dim.value) != 0
    attr |= Attribute::Cursive if (bits & Attribute::Cursive.value) != 0
    attr |= Attribute::Hidden if (bits & Attribute::Hidden.value) != 0
    attr |= Attribute::Strikethrough if (bits & Attribute::Strikethrough.value) != 0
    attr
  end

  def self.to_abi_event(event : Event::Any) : Termisu::FFI::ABI::Event
    case event
    when Event::Key
      key_event(event)
    when Event::Mouse
      mouse_event(event)
    when Event::Resize
      resize_event(event)
    when Event::Tick
      tick_event(event)
    when Event::ModeChange
      mode_change_event(event)
    else
      blank_event
    end
  end

  private def self.key_event(event : Event::Key) : Termisu::FFI::ABI::Event
    out = blank_event
    out.event_type = Termisu::FFI::EventType::Key.value
    out.modifiers = event.modifiers.value.to_u8
    out.key_code = event.key.value
    out.key_char = event.char.try(&.ord) || -1
    out
  end

  private def self.mouse_event(event : Event::Mouse) : Termisu::FFI::ABI::Event
    out = blank_event
    out.event_type = Termisu::FFI::EventType::Mouse.value
    out.modifiers = event.modifiers.value.to_u8
    out.mouse_x = event.x
    out.mouse_y = event.y
    out.mouse_button = event.button.value
    out.mouse_motion = event.motion? ? 1_u8 : 0_u8
    out
  end

  private def self.resize_event(event : Event::Resize) : Termisu::FFI::ABI::Event
    out = blank_event
    out.event_type = Termisu::FFI::EventType::Resize.value
    out.resize_width = event.width
    out.resize_height = event.height
    if old_width = event.old_width
      out.resize_old_width = old_width
      out.resize_old_height = event.old_height || 0
      out.resize_has_old = 1_u8
    end
    out
  end

  private def self.tick_event(event : Event::Tick) : Termisu::FFI::ABI::Event
    out = blank_event
    out.event_type = Termisu::FFI::EventType::Tick.value
    out.tick_frame = event.frame
    out.tick_elapsed_ns = event.elapsed.total_nanoseconds
    out.tick_delta_ns = event.delta.total_nanoseconds
    out.tick_missed_ticks = event.missed_ticks
    out
  end

  private def self.mode_change_event(event : Event::ModeChange) : Termisu::FFI::ABI::Event
    out = blank_event
    out.event_type = Termisu::FFI::EventType::ModeChange.value
    out.mode_current = event.mode.value.to_u32
    if previous = event.previous_mode
      out.mode_previous = previous.value.to_u32
      out.mode_has_previous = 1_u8
    end
    out
  end

  def self.blank_event : Termisu::FFI::ABI::Event
    event = uninitialized Termisu::FFI::ABI::Event

    event.event_type = Termisu::FFI::EventType::None.value
    event.modifiers = 0_u8
    event.reserved = 0_u16

    event.key_code = 0
    event.key_char = -1

    event.mouse_x = 0
    event.mouse_y = 0
    event.mouse_button = 0
    event.mouse_motion = 0_u8

    event.resize_width = 0
    event.resize_height = 0
    event.resize_old_width = 0
    event.resize_old_height = 0
    event.resize_has_old = 0_u8

    event.tick_frame = 0_u64
    event.tick_elapsed_ns = 0_i64
    event.tick_delta_ns = 0_i64
    event.tick_missed_ticks = 0_u64

    event.mode_current = 0_u32
    event.mode_previous = 0_u32
    event.mode_has_previous = 0_u8

    event
  end
end
