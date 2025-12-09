# Input parser for terminal escape sequences.
#
# Parses raw terminal input into structured Event objects.
# Supports CSI sequences (arrows, function keys, nav), SS3 sequences,
# Alt+key combinations, Ctrl+key combinations, and mouse events.
#
# Example:
# ```
# parser = Termisu::Input::Parser.new(reader)
# if event = parser.poll_event(1000)
#   puts "Got event: #{event}"
# end
# ```
class Termisu::Input::Parser
  Log = Termisu::Logs::Input

  # Timeout in milliseconds to distinguish ESC key from escape sequences.
  # 50ms matches termbox/tcell behavior.
  ESCAPE_TIMEOUT_MS = 50

  # Maximum escape sequence length before giving up.
  MAX_SEQUENCE_LENGTH = 32

  # Mouse protocol bit mask for motion events (bit 5).
  # When set, indicates mouse moved while button was held.
  MOUSE_MOTION_BIT = 32

  # CSI final character to Key mapping.
  CSI_KEYS = {
    'A' => Key::Up,
    'B' => Key::Down,
    'C' => Key::Right,
    'D' => Key::Left,
    'H' => Key::Home,
    'F' => Key::End,
    'Z' => Key::BackTab,
    'P' => Key::F1,
    'Q' => Key::F2,
    'R' => Key::F3,
    'S' => Key::F4,
  }

  # Tilde sequence code to Key mapping (\e[N~).
  TILDE_KEYS = {
     1 => Key::Home,
     2 => Key::Insert,
     3 => Key::Delete,
     4 => Key::End,
     5 => Key::PageUp,
     6 => Key::PageDown,
     7 => Key::Home,
     8 => Key::End,
    11 => Key::F1,
    12 => Key::F2,
    13 => Key::F3,
    14 => Key::F4,
    15 => Key::F5,
    17 => Key::F6,
    18 => Key::F7,
    19 => Key::F8,
    20 => Key::F9,
    21 => Key::F10,
    23 => Key::F11,
    24 => Key::F12,
    25 => Key::F13,
    26 => Key::F14,
    28 => Key::F15,
    29 => Key::F16,
    31 => Key::F17,
    32 => Key::F18,
    33 => Key::F19,
    34 => Key::F20,
  }

  # SS3 final character to Key mapping (\eO...).
  SS3_KEYS = {
    'P' => Key::F1,
    'Q' => Key::F2,
    'R' => Key::F3,
    'S' => Key::F4,
    'A' => Key::Up,
    'B' => Key::Down,
    'C' => Key::Right,
    'D' => Key::Left,
    'H' => Key::Home,
    'F' => Key::End,
  }

  # Linux console function keys use \e[[A through \e[[E.
  LINUX_CONSOLE_KEYS = {
    "[[A" => Key::F1,
    "[[B" => Key::F2,
    "[[C" => Key::F3,
    "[[D" => Key::F4,
    "[[E" => Key::F5,
  }

  @reader : Reader

  def initialize(@reader : Reader)
  end

  # Polls for an input event with optional timeout.
  #
  # - `timeout_ms` - Timeout in milliseconds (-1 for blocking)
  #
  # Returns an Event or nil if timeout/no data.
  def poll_event(timeout_ms : Int32 = -1) : Event?
    unless @reader.wait_for_data(timeout_ms < 0 ? Int32::MAX : timeout_ms)
      return nil
    end

    byte = @reader.read_byte
    return nil unless byte

    parse_byte(byte)
  end

  # Parses a single byte, potentially reading more for escape sequences.
  #
  # Note: Terminals cannot distinguish between certain keys and Ctrl combinations:
  # - Tab sends 0x09 (same as Ctrl+I)
  # - Enter sends 0x0D (same as Ctrl+M)
  # - Backspace may send 0x08 (same as Ctrl+H)
  # We treat these as their dedicated keys without Ctrl modifier.
  #
  # Also: Modifier keys alone (Ctrl, Alt, Shift) don't send any bytes in
  # standard terminal input. We can only detect them combined with other keys.
  private def parse_byte(byte : UInt8) : Event
    case byte
    when 0x1B # ESC - could be escape key or start of sequence
      parse_escape_sequence
    when 0x00 # Ctrl+Space or Ctrl+@
      Events::Key.new(Key::Space, Modifier::Ctrl)
    when 0x08 # Backspace (Ctrl+H on some terminals, but treat as Backspace)
      Events::Key.new(Key::Backspace)
    when 0x09 # Tab (technically Ctrl+I, but always treat as Tab)
      Events::Key.new(Key::Tab)
    when 0x0A # Line feed (Ctrl+J) - treat as Enter
      Events::Key.new(Key::Enter)
    when 0x0D # Carriage return (Ctrl+M) - treat as Enter
      Events::Key.new(Key::Enter)
    when 0x01..0x1A # Ctrl+A through Ctrl+Z (excluding special cases above)
      key = Key.from_char(('a'.ord + byte - 1).chr)
      Events::Key.new(key, Modifier::Ctrl)
    when 0x7F # DEL (Backspace on most terminals)
      Events::Key.new(Key::Backspace)
    else
      # Printable character
      key = Key.from_char(byte.chr)
      Events::Key.new(key)
    end
  end

  # Parses an escape sequence starting with ESC (0x1B).
  private def parse_escape_sequence : Event
    # Check if more data follows (escape sequence) or just ESC key
    unless @reader.wait_for_data(ESCAPE_TIMEOUT_MS)
      return Events::Key.new(Key::Escape)
    end

    byte = @reader.peek_byte
    unless byte
      return Events::Key.new(Key::Escape)
    end

    case byte
    when '['.ord.to_u8  # CSI sequence: \e[...
      @reader.read_byte # consume '['
      parse_csi_sequence
    when 'O'.ord.to_u8  # SS3 sequence: \eO... (F1-F4, some arrows)
      @reader.read_byte # consume 'O'
      parse_ss3_sequence
    else
      # Alt+key: \e followed by printable char
      @reader.read_byte # consume the char
      key = Key.from_char(byte.chr)
      Events::Key.new(key, Modifier::Alt)
    end
  end

  # Parses a CSI sequence: \e[...
  #
  # CSI format: \e [ <params> <intermediate> <final>
  # Final chars are 0x40-0x7E (@A-Z[\]^_`a-z{|}~)
  private def parse_csi_sequence : Event
    buffer = String::Builder.new

    while byte = @reader.read_byte
      char = byte.chr

      # Check for SGR mouse: \e[<...
      if buffer.empty? && char == '<'
        return parse_sgr_mouse
      end

      # Check for normal mouse: \e[M...
      if buffer.empty? && char == 'M'
        return parse_normal_mouse
      end

      if byte >= 0x40 && byte <= 0x7E
        # Final character - determines the key
        params = buffer.to_s
        return decode_csi_key(params, char)
      end

      buffer << char

      # Safety limit
      if buffer.bytesize >= MAX_SEQUENCE_LENGTH
        Log.warn { "CSI sequence too long, aborting" }
        return Events::Key.new(Key::Unknown)
      end
    end

    Events::Key.new(Key::Unknown)
  end

  # Decodes a CSI sequence into a KeyEvent using hash lookups.
  # Handles standard CSI sequences, Kitty keyboard protocol, and modifyOtherKeys.
  private def decode_csi_key(params : String, final : Char) : Events::Key
    # Kitty keyboard protocol: CSI codepoint ; modifiers u
    # or: CSI codepoint ; modifiers : event_type u
    if final == 'u'
      return parse_kitty_key(params)
    end

    modifiers = parse_modifiers(params)

    # Check for tilde sequences (\e[N~ or \e[N;M~)
    if final == '~'
      parts = params.split(';')
      code = parts.first?.try(&.to_i?) || 0

      # modifyOtherKeys: CSI 27 ; modifier ; keycode ~
      if code == 27 && parts.size >= 3
        return parse_modify_other_keys(parts)
      end

      key = TILDE_KEYS[code]? || Key::Unknown
      return Events::Key.new(key, modifiers)
    end

    # Check for Linux console sequences (\e[[A etc.)
    sequence = "[#{params}#{final}"
    if key = LINUX_CONSOLE_KEYS[sequence]?
      return Events::Key.new(key, modifiers)
    end

    # Standard CSI key lookup
    key = CSI_KEYS[final]? || Key::Unknown
    Events::Key.new(key, modifiers)
  end

  # Parses Kitty keyboard protocol sequence.
  # Format: CSI codepoint ; modifiers u
  # or: CSI codepoint ; modifiers : event_type u
  #
  # Codepoint is the Unicode codepoint of the key.
  # Modifiers use the same encoding as xterm (1 + shift + alt*2 + ctrl*4 + meta*8).
  private def parse_kitty_key(params : String) : Events::Key
    # Handle colon separator for event type (e.g., "97;5:1" for Ctrl+A press)
    clean_params = params.split(':').first || params
    parts = clean_params.split(';')

    codepoint = parts[0]?.try(&.to_i?) || 0
    mod_code = parts[1]?.try(&.to_i?) || 1

    modifiers = Modifier.from_xterm_code(mod_code)

    # Convert codepoint to key
    key = codepoint_to_key(codepoint)

    Events::Key.new(key, modifiers)
  end

  # Parses modifyOtherKeys sequence.
  # Format: CSI 27 ; modifier ; keycode ~
  private def parse_modify_other_keys(parts : Array(String)) : Events::Key
    mod_code = parts[1]?.try(&.to_i?) || 1
    keycode = parts[2]?.try(&.to_i?) || 0

    modifiers = Modifier.from_xterm_code(mod_code)
    key = codepoint_to_key(keycode)

    Events::Key.new(key, modifiers)
  end

  # Kitty protocol codepoint to Key mapping for special keys.
  # These codepoints are specific to the Kitty keyboard protocol.
  KITTY_CODEPOINTS = {
       27 => Key::Escape,
       13 => Key::Enter,
        9 => Key::Tab,
      127 => Key::Backspace,
        8 => Key::Backspace,
    57358 => Key::CapsLock,
    57359 => Key::ScrollLock,
    57360 => Key::NumLock,
    57361 => Key::PrintScreen,
    57362 => Key::Pause,
    57376 => Key::F13,
    57377 => Key::F14,
    57378 => Key::F15,
    57379 => Key::F16,
    57380 => Key::F17,
    57381 => Key::F18,
    57382 => Key::F19,
    57383 => Key::F20,
    57384 => Key::F21,
    57385 => Key::F22,
    57386 => Key::F23,
    57387 => Key::F24,
  }

  # Converts a Unicode codepoint to a Key enum value.
  # Used by enhanced keyboard protocols that send codepoints.
  private def codepoint_to_key(codepoint : Int32) : Key
    # Check special keys first via hash lookup
    if key = KITTY_CODEPOINTS[codepoint]?
      return key
    end

    # Try to convert as a character
    if codepoint > 0 && codepoint <= 0x10FFFF
      begin
        Key.from_char(codepoint.chr)
      rescue
        Key::Unknown
      end
    else
      Key::Unknown
    end
  end

  # Parses modifier code from CSI params string.
  # Format: "1;2" where 2 is the modifier code.
  private def parse_modifiers(params : String) : Modifier
    return Modifier::None unless params.includes?(';')

    parts = params.split(';')
    return Modifier::None if parts.size < 2

    mod_code = parts[1].to_i? || 1
    Modifier.from_xterm_code(mod_code)
  end

  # Parses an SS3 sequence: \eO...
  #
  # SS3 sequences are used for F1-F4 and some arrow keys.
  private def parse_ss3_sequence : Event
    byte = @reader.read_byte
    unless byte
      return Events::Key.new(Key::Unknown)
    end

    key = SS3_KEYS[byte.chr]? || Key::Unknown
    Events::Key.new(key)
  end

  # Parses SGR extended mouse protocol (mode 1006).
  # Format: \e[<Cb;Cx;CyM (press) or \e[<Cb;Cx;Cym (release)
  private def parse_sgr_mouse : Event
    result = read_sgr_sequence
    return Events::Key.new(Key::Unknown) unless result

    raw_params, is_release = result
    parse_sgr_params_to_event(raw_params, is_release) || Events::Key.new(Key::Unknown)
  end

  # Reads bytes until SGR mouse sequence terminator ('M' or 'm').
  #
  # Returns tuple of (raw params string, is_release flag) or nil if overflow/EOF.
  private def read_sgr_sequence : {String, Bool}?
    buffer = String::Builder.new

    while byte = @reader.read_byte
      case byte.chr
      when 'M' then return {buffer.to_s, false}
      when 'm' then return {buffer.to_s, true}
      else
        buffer << byte.chr
        if buffer.bytesize >= MAX_SEQUENCE_LENGTH
          Log.warn { "SGR mouse sequence too long" }
          return nil
        end
      end
    end

    nil
  end

  # Parses SGR mouse params (Cb;Cx;Cy) into a Mouse event.
  #
  # - `raw_params`: The raw parameter string (e.g., "0;45;12")
  # - `is_release`: Whether this is a release event (lowercase 'm' terminator)
  #
  # Returns Mouse event or nil if params are invalid.
  private def parse_sgr_params_to_event(raw_params : String, is_release : Bool) : Events::Mouse?
    parts = raw_params.split(';')
    return nil unless parts.size >= 3

    cb = parts[0].to_i? || return nil
    x = parts[1].to_i? || 1
    y = parts[2].to_i? || 1

    button = Events::MouseButton.from_cb(cb)
    # Wheel events are instantaneous - they don't have release events
    is_wheel = button.wheel_up? || button.wheel_down? || button.wheel_left? || button.wheel_right?
    button = Events::MouseButton::Release if is_release && !is_wheel

    modifiers = Modifier.from_mouse_cb(cb)
    motion = (cb & MOUSE_MOTION_BIT) != 0

    Events::Mouse.new(x, y, button, modifiers, motion)
  end

  # Parses normal mouse protocol (mode 1000).
  # Format: \e[MCbCxCy (6 bytes total, Cb/Cx/Cy are raw bytes + 32)
  private def parse_normal_mouse : Event
    # Read 3 more bytes: Cb, Cx, Cy
    cb_byte = @reader.read_byte
    cx_byte = @reader.read_byte
    cy_byte = @reader.read_byte

    unless cb_byte && cx_byte && cy_byte
      return Events::Key.new(Key::Unknown)
    end

    # Decode: subtract 32 from each
    cb = cb_byte.to_i32 - 32
    cx = cx_byte.to_i32 - 32
    cy = cy_byte.to_i32 - 32

    # Clamp coordinates to valid range (1-223)
    cx = cx.clamp(1, 223)
    cy = cy.clamp(1, 223)

    button = Events::MouseButton.from_cb(cb)
    modifiers = Modifier.from_mouse_cb(cb)
    motion = (cb & MOUSE_MOTION_BIT) != 0

    Events::Mouse.new(cx, cy, button, modifiers, motion)
  end
end
