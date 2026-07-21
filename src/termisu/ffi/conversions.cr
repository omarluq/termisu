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
  rescue ex : ArgumentError
    raise ArgumentError.new("Invalid Unicode codepoint #{codepoint}: #{ex.message || ex.class.name}")
  end

  def self.style_from_ptr(style : Termisu::FFI::ABI::CellStyle*) : {Color, Color, Attribute}
    return {Color.white, Color.default, Attribute::None} if style.null?

    style_from_abi(style.value)
  end

  def self.style_from_abi(style : Termisu::FFI::ABI::CellStyle) : {Color, Color, Attribute}
    fg = color_from_abi(style.fg)
    bg = color_from_abi(style.bg)
    attr = attr_from_bits(style.attr)
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
    abi = blank_event
    write_abi_event(event, pointerof(abi))
    abi
  end

  # Writes `event` into the caller's struct in place, without zeroing it
  # first. ABI readers dispatch on event_type and only touch that type's
  # fields (see readEvent in javascript/core/src/structs.ts): event_type and
  # modifiers are always read; key_*, mouse_*, resize_*, tick_*, mode_* and
  # preedit_* only for their own type, with resize_old_*/mode_previous
  # gated behind their has_* flags. Each writer below sets exactly that
  # read-set (writing explicit zeros for absent optional fields), so any
  # other byte in the caller's buffer may keep stale content.
  def self.write_abi_event(event : Event::Any, out_event : Termisu::FFI::ABI::Event*) : Nil
    case event
    when Event::Key
      write_key_event(event, out_event)
    when Event::Mouse
      write_mouse_event(event, out_event)
    when Event::Resize
      write_resize_event(event, out_event)
    when Event::Tick
      write_tick_event(event, out_event)
    when Event::ModeChange
      write_mode_change_event(event, out_event)
    when Event::Preedit
      write_preedit_event(event, out_event)
    else
      write_blank_event(out_event)
    end
  end

  # No-event marker (poll timeout): readers only touch event_type and
  # modifiers for a None event; key_char = -1 is kept as the "no char"
  # sentinel blank_event has always guaranteed.
  def self.write_blank_event(out_event : Termisu::FFI::ABI::Event*) : Nil
    out_event.value.event_type = Termisu::FFI::EventType::None.value
    out_event.value.modifiers = 0_u8
    out_event.value.key_char = -1
  end

  private def self.write_key_event(event : Event::Key, out_event : Termisu::FFI::ABI::Event*) : Nil
    out_event.value.event_type = Termisu::FFI::EventType::Key.value
    out_event.value.modifiers = event.modifiers.value.to_u8
    out_event.value.key_code = event.key.value
    out_event.value.key_char = event.char.try(&.ord) || -1
  end

  private def self.write_mouse_event(event : Event::Mouse, out_event : Termisu::FFI::ABI::Event*) : Nil
    out_event.value.event_type = Termisu::FFI::EventType::Mouse.value
    out_event.value.modifiers = event.modifiers.value.to_u8
    out_event.value.mouse_x = event.x
    out_event.value.mouse_y = event.y
    out_event.value.mouse_button = event.button.value
    out_event.value.mouse_motion = event.motion? ? 1_u8 : 0_u8
  end

  private def self.write_resize_event(event : Event::Resize, out_event : Termisu::FFI::ABI::Event*) : Nil
    out_event.value.event_type = Termisu::FFI::EventType::Resize.value
    out_event.value.modifiers = 0_u8
    out_event.value.resize_width = event.width
    out_event.value.resize_height = event.height
    old_width = event.old_width
    old_height = event.old_height
    if old_width && old_height
      out_event.value.resize_old_width = old_width
      out_event.value.resize_old_height = old_height
      out_event.value.resize_has_old = 1_u8
    else
      out_event.value.resize_old_width = 0
      out_event.value.resize_old_height = 0
      out_event.value.resize_has_old = 0_u8
    end
  end

  private def self.write_tick_event(event : Event::Tick, out_event : Termisu::FFI::ABI::Event*) : Nil
    out_event.value.event_type = Termisu::FFI::EventType::Tick.value
    out_event.value.modifiers = 0_u8
    out_event.value.tick_frame = event.frame
    out_event.value.tick_elapsed_ns = event.elapsed.total_nanoseconds.to_i64
    out_event.value.tick_delta_ns = event.delta.total_nanoseconds.to_i64
    out_event.value.tick_missed_ticks = event.missed_ticks
  end

  private def self.write_mode_change_event(event : Event::ModeChange, out_event : Termisu::FFI::ABI::Event*) : Nil
    out_event.value.event_type = Termisu::FFI::EventType::ModeChange.value
    out_event.value.modifiers = 0_u8
    out_event.value.mode_current = event.mode.value.to_u32
    if previous = event.previous_mode
      out_event.value.mode_previous = previous.value.to_u32
      out_event.value.mode_has_previous = 1_u8
    else
      out_event.value.mode_previous = 0_u32
      out_event.value.mode_has_previous = 0_u8
    end
  end

  private def self.write_preedit_event(event : Event::Preedit, out_event : Termisu::FFI::ABI::Event*) : Nil
    out_event.value.event_type = Termisu::FFI::EventType::Preedit.value
    out_event.value.modifiers = 0_u8

    # Copy UTF-8 bytes into the inline buffer, stopping before any char that
    # would overflow it so the text is never split mid-codepoint. Trailing
    # bytes stay 0.
    buf = StaticArray(UInt8, Termisu::FFI::PREEDIT_TEXT_CAPACITY).new(0_u8)
    len = 0
    event.text.each_char do |char|
      break if len + char.bytesize > Termisu::FFI::PREEDIT_TEXT_CAPACITY
      char.each_byte do |byte|
        buf[len] = byte
        len += 1
      end
    end
    out_event.value.preedit_text = buf
    out_event.value.preedit_len = len.to_u8
  end

  # Fully zeroed None event, deterministic across every field. The FFI poll
  # hot path uses write_blank_event instead, which skips the memset.
  def self.blank_event : Termisu::FFI::ABI::Event
    event = uninitialized Termisu::FFI::ABI::Event
    pointerof(event).as(UInt8*).clear(sizeof(Termisu::FFI::ABI::Event))

    event.event_type = Termisu::FFI::EventType::None.value
    event.key_char = -1
    event
  end
end
