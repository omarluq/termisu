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

  # Tilde sequence code to Key mapping (`\e[N~` format).
  #
  # Maps numeric codes from CSI tilde sequences to keys.
  # Codes 1-8 are navigation keys, 11-24 are function keys F1-F12.
  # Codes 25-34 are extended function keys F13-F20 (rarely used).
  #
  # Note: Some codes are skipped (9-10, 16, 22, 27, 30) for historical
  # terminal compatibility reasons. Codes 1/7 and 4/8 are duplicates
  # (Home/End) because different terminals use different codes.
  #
  # Reference: XTerm ctlseqs, VT220 sequences.
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
  @protocol_active : Bool = false
  # One-shot de-duplication guard. When a CSI-u event reports an associated
  # text char, some terminals ALSO echo that same char as a raw UTF-8 byte
  # (notably IME commits). We remember the just-emitted protocol char here so
  # the immediately-following raw byte, IF it is the exact same char, can be
  # swallowed as a duplicate. It is consumed (cleared) by the very next byte —
  # so plain unmodified keys (which arrive as raw bytes under the 17u flag set,
  # since report_all_keys is off) are never wrongly dropped.
  @dup_guard : Char? = nil

  def initialize(@reader : Reader)
  end

  # Reads a complete UTF-8 character (1-4 bytes) starting from the given lead byte.
  # Consumes the additional continuation bytes from the reader.
  # Returns nil if incomplete, invalid, or not UTF-8 text.
  #
  # Note on Hangul/IME: This receives *committed* characters after IME composition
  # completes (e.g. after typing jamo for a full syllable). Preedit/composing text
  # during input is typically handled by the terminal emulator or OS IME overlay,
  # not delivered as key events here. Full preedit support would require terminal-
  # specific protocols (e.g. kitty's input protocol extensions or IM protocol).
  private def read_utf8_char(first_byte : UInt8) : Char?
    return first_byte.chr if first_byte < 0x80 # ASCII fast path

    # Sequence length from the lead byte: count the leading 1-bits (2..4 for a
    # valid multibyte lead). Anything else (lone continuation byte, 0xFF, etc.)
    # is rejected here; full validity is confirmed by valid_encoding? below.
    len = (~first_byte).leading_zeros_count.to_i
    return nil unless 2 <= len <= 4

    bytes = Bytes.new(len)
    bytes[0] = first_byte

    (1...len).each do |i|
      # wait_for_data reuses the split-read tolerance so a char fragmented
      # across two reads survives; peek + confirm before consuming so a
      # non-continuation byte is left in the buffer rather than swallowed.
      return nil unless @reader.wait_for_data(ESCAPE_TIMEOUT_MS)
      b = @reader.peek_byte
      return nil unless b && (b & 0xC0) == 0x80 # continuation 10xxxxxx
      @reader.read_byte
      bytes[i] = b
    end

    # valid_encoding? is a full RFC-3629 check: it rejects overlong encodings,
    # surrogates, and anything above U+10FFFF. String.new never raises on bad
    # UTF-8 (it yields U+FFFD), so no begin/rescue is needed.
    s = String.new(bytes)
    s.valid_encoding? ? s[0]? : nil
  end

  # Polls for an input event with optional timeout.
  #
  # - `timeout_ms` - Timeout in milliseconds (-1 for blocking)
  #
  # Returns an Event or nil if timeout/no data.
  def poll_event(timeout_ms : Int32 = -1) : Event::Any?
    unless @reader.wait_for_data(timeout_ms < 0 ? Int32::MAX : timeout_ms)
      return
    end

    byte = @reader.read_byte
    return unless byte

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
  private def parse_byte(byte : UInt8) : Event::Any
    # Snapshot + clear the one-shot dup guard: it only matches a raw byte that
    # arrives IMMEDIATELY after the CSI-u event that set it (handled in the
    # printable branch below). Any other byte clears it. The escape branch may
    # set a fresh guard for the *next* call.
    dup = @dup_guard
    @dup_guard = nil
    case byte
    when 0x1B # ESC - could be escape key or start of sequence
      parse_escape_sequence
    when 0x00 # Ctrl+Space or Ctrl+@
      Event::Key.new(Key::Space, Modifier::Ctrl)
    when 0x08 # Backspace (Ctrl+H on some terminals, but treat as Backspace)
      Event::Key.new(Key::Backspace)
    when 0x09 # Tab (technically Ctrl+I, but always treat as Tab)
      Event::Key.new(Key::Tab)
    when 0x0A # Line feed (Ctrl+J) - treat as Enter
      Event::Key.new(Key::Enter)
    when 0x0D # Carriage return (Ctrl+M) - treat as Enter
      Event::Key.new(Key::Enter)
    when 0x01..0x1A # Ctrl+A through Ctrl+Z (excluding special cases above)
      key = Key.from_char(('a'.ord + byte - 1).chr)
      Event::Key.new(key, Modifier::Ctrl)
    when 0x7F # DEL (Backspace on most terminals)
      Event::Key.new(Key::Backspace)
    else
      # Printable character - support full UTF-8 (Hangul, CJK, etc. for text input).
      # Always read the full UTF-8 char first (so multibyte continuation bytes are
      # consumed even when we end up discarding it — otherwise they'd be misparsed).
      c = read_utf8_char(byte)
      return Event::Key.new(Key::Unknown) unless c

      # Under the Kitty protocol (report_text), plain unmodified keys still arrive
      # as raw bytes (report_all_keys is off), so we must NOT blanket-drop them.
      # Only swallow a raw byte that exactly duplicates the char just emitted by
      # the immediately-preceding CSI-u text event (a terminal echoing an IME
      # commit on both channels).
      return Event::Key.new(Key::Unknown) if @protocol_active && dup == c

      key = Key.from_char(c) || Key::Unknown
      Event::Key.new(key, char: c)
    end
  end

  # Parses an escape sequence starting with ESC (0x1B).
  private def parse_escape_sequence : Event::Any
    # Check if more data follows (escape sequence) or just ESC key
    unless @reader.wait_for_data(ESCAPE_TIMEOUT_MS)
      return Event::Key.new(Key::Escape)
    end

    byte = @reader.peek_byte
    unless byte
      return Event::Key.new(Key::Escape)
    end

    case byte
    when '['.ord.to_u8  # CSI sequence: \e[...
      @reader.read_byte # consume '['
      parse_csi_sequence
    when 'O'.ord.to_u8  # SS3 sequence: \eO... (F1-F4, some arrows)
      @reader.read_byte # consume 'O'
      parse_ss3_sequence
    else
      # Alt+key: \e followed by printable char (UTF-8 capable)
      @reader.read_byte # consume the (first) char byte
      c = read_utf8_char(byte)
      key = c ? (Key.from_char(c) || Key::Unknown) : Key::Unknown
      Event::Key.new(key, Modifier::Alt, char: c)
    end
  end

  # Parses a CSI sequence: \e[...
  #
  # CSI format: \e [ <params> <intermediate> <final>
  # Final chars are 0x40-0x7E (@A-Z[\]^_`a-z{|}~)
  private def parse_csi_sequence : Event::Any
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
        return Event::Key.new(Key::Unknown)
      end
    end

    Event::Key.new(Key::Unknown)
  end

  # Decodes a CSI sequence into a KeyEvent using hash lookups.
  # Handles standard CSI sequences, Kitty keyboard protocol, and modifyOtherKeys.
  # Returns Any because kitty text events with codepoint 0 are emitted as Preedit.
  private def decode_csi_key(params : String, final : Char) : Event::Any
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
      return Event::Key.new(key, modifiers)
    end

    # Check for Linux console sequences (\e[[A etc.)
    sequence = "[#{params}#{final}"
    if key = LINUX_CONSOLE_KEYS[sequence]?
      return Event::Key.new(key, modifiers)
    end

    # Standard CSI key lookup
    key = CSI_KEYS[final]? || Key::Unknown
    Event::Key.new(key, modifiers)
  end

  # Parses Kitty keyboard protocol sequence.
  # Format: CSI codepoint ; modifiers u
  # or: CSI codepoint ; modifiers : event_type u
  #
  # Codepoint is the Unicode codepoint of the key.
  # Modifiers use the same encoding as xterm (1 + shift + alt*2 + ctrl*4 + meta*8).
  # With report_text, a 3rd field carries the produced text codepoints (prefer for .char).
  private def parse_kitty_key(params : String) : Event::Any
    # Fields are ';'-separated: codepoint ; modifiers ; text. The ':' separator is
    # used *within* fields — alternate keys in the codepoint field
    # (unicode:shifted:base), an event type in the modifier field (mods:event_type),
    # and MULTIPLE codepoints in the text field (cp1:cp2:...). Split on ';' first and
    # strip ':' only from the codepoint/modifier fields; never from the text field,
    # or multi-codepoint text (e.g. composed Hangul jamo) would be truncated.
    parts = params.split(';')

    codepoint = parts[0]?.try(&.split(':').first).try(&.to_i?) || 0
    mod_code = parts[1]?.try(&.split(':').first).try(&.to_i?) || 1
    text_param = parts[2]?

    modifiers = Modifier.from_xterm_code(mod_code)

    text_str = build_text_from_codepoints(text_param)

    # Prefer associated text (report_text) for the actual inserted char (e.g. shift+a gives 'A' in text)
    c = text_str[0]? || ((codepoint > 0 && codepoint <= 0x10FFFF) ? (codepoint.chr rescue nil) : nil)

    # If we saw a text-producing CSI report, terminal is using protocol for chars too (report_all+text or similar);
    # skip raw byte path for printables from now to avoid duplicates.
    if c && c.printable? && c.ord >= 32
      @protocol_active = true
    end

    if codepoint == 0
      # Pure text event (no associated key), typically from IME or direct text input.
      # Emit as Preedit so the TUI can show composing state with underline (e.g.
      # building Hangul jamo -> syllable). An EMPTY text here is the terminal
      # signalling "preedit cleared" — emit Preedit("") so consumers can clear stale
      # composition UI, rather than dropping it as Key::Unknown. On commit the final
      # syllable arrives as a normal Key+char (or another report).
      @protocol_active = true
      return Event::Preedit.new(text_str)
    end

    key = codepoint_to_key(codepoint)
    # Arm the one-shot dup guard so a duplicate raw echo of this exact char
    # (same byte immediately following) is swallowed; plain keys never match it.
    @dup_guard = c if c && c.printable? && c.ord >= 32
    Event::Key.new(key, modifiers, char: c)
  end

  # Parses modifyOtherKeys sequence.
  # Format: CSI 27 ; modifier ; keycode ~
  private def parse_modify_other_keys(parts : Array(String)) : Event::Key
    mod_code = parts[1]?.try(&.to_i?) || 1
    keycode = parts[2]?.try(&.to_i?) || 0

    modifiers = Modifier.from_xterm_code(mod_code)
    key = codepoint_to_key(keycode)
    c = (keycode > 0 && keycode <= 0x10FFFF) ? (keycode.chr rescue nil) : nil

    # If modify reports a printable via CSI, the terminal is using the protocol
    # for text; arm the one-shot dup guard so only a duplicate raw echo of this
    # exact char is swallowed (plain raw keys keep flowing).
    if c && c.printable? && c.ord >= 32
      @protocol_active = true
      @dup_guard = c
    end

    Event::Key.new(key, modifiers, char: c)
  end

  # Whether `cp` is a scalar Unicode codepoint that maps to a real Char: in
  # range and not a UTF-16 surrogate (U+D800..U+DFFF), which `Int#chr` would
  # otherwise accept. Filtering here keeps the intent explicit and surrogate-safe.
  private def valid_codepoint?(cp : Int32) : Bool
    cp >= 0 && cp <= Char::MAX_CODEPOINT && !(0xD800..0xDFFF).includes?(cp)
  end

  private def build_text_from_codepoints(text_param : String?) : String
    return "" if text_param.nil? || text_param.empty?

    String.build do |io|
      text_param.split(':').each do |part|
        cp = part.to_i?
        io << cp.chr if cp && valid_codepoint?(cp)
      end
    end
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
  private def parse_ss3_sequence : Event::Any
    byte = @reader.read_byte
    unless byte
      return Event::Key.new(Key::Unknown)
    end

    key = SS3_KEYS[byte.chr]? || Key::Unknown
    Event::Key.new(key)
  end

  # Parses SGR extended mouse protocol (mode 1006).
  # Format: \e[<Cb;Cx;CyM (press) or \e[<Cb;Cx;Cym (release)
  private def parse_sgr_mouse : Event::Any
    result = read_sgr_sequence
    return Event::Key.new(Key::Unknown) unless result

    raw_params, is_release = result
    parse_sgr_params_to_event(raw_params, is_release) || Event::Key.new(Key::Unknown)
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
          return
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
  private def parse_sgr_params_to_event(raw_params : String, is_release : Bool) : Event::Mouse?
    parts = raw_params.split(';')
    return unless parts.size >= 3

    cb = parts[0].to_i? || return
    x = parts[1].to_i? || 1
    y = parts[2].to_i? || 1

    button = Event::Mouse::Button.from_cb(cb)
    # Wheel events are instantaneous - they don't have release events
    is_wheel = button.wheel_up? || button.wheel_down? || button.wheel_left? || button.wheel_right?
    button = Event::Mouse::Button::Release if is_release && !is_wheel

    modifiers = Modifier.from_mouse_cb(cb)
    motion = (cb & MOUSE_MOTION_BIT) != 0

    Event::Mouse.new(x, y, button, modifiers, motion)
  end

  # Parses normal mouse protocol (mode 1000).
  # Format: \e[MCbCxCy (6 bytes total, Cb/Cx/Cy are raw bytes + 32)
  private def parse_normal_mouse : Event::Any
    # Read 3 more bytes: Cb, Cx, Cy
    cb_byte = @reader.read_byte
    cx_byte = @reader.read_byte
    cy_byte = @reader.read_byte

    unless cb_byte && cx_byte && cy_byte
      return Event::Key.new(Key::Unknown)
    end

    # Decode: subtract 32 from each
    cb = cb_byte.to_i32 - 32
    cx = cx_byte.to_i32 - 32
    cy = cy_byte.to_i32 - 32

    # Clamp coordinates to valid range (1-223)
    cx = cx.clamp(1, 223)
    cy = cy.clamp(1, 223)

    button = Event::Mouse::Button.from_cb(cb)
    modifiers = Modifier.from_mouse_cb(cb)
    motion = (cb & MOUSE_MOTION_BIT) != 0

    Event::Mouse.new(cx, cy, button, modifiers, motion)
  end
end
