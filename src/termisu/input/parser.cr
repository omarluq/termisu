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

  # Bracketed paste boundary codes, also delivered as `\e[N~` sequences.
  #
  # Kept out of TILDE_KEYS because they are not keystrokes: they only mark
  # where a paste begins and ends. A terminal sends them exclusively while DEC
  # private mode 2004 is on (see `Terminal#enable_bracketed_paste`), which is
  # why an application that never enables the mode cannot observe them.
  PASTE_KEYS = {
    200 => Key::PasteStart,
    201 => Key::PasteEnd,
  }

  # The bytes that follow ESC in the end marker, matched literally.
  #
  # Inside a paste the terminator is found by comparing raw bytes, never by
  # parsing an escape sequence. Two ways the parsing route loses it: the fd can
  # run dry at the marker's ESC and the rest arrive after ESCAPE_TIMEOUT_MS (the
  # ESC then resolves as a bare Escape and `[201~` lands as text), and paste
  # CONTENT ending in a truncated escape can swallow the marker's ESC into its
  # own Alt-key or CSI-parameter branch. Both wedge a consumer that tracks
  # PasteStart/PasteEnd as a boolean, since the mode never closes.
  PASTE_END_TAIL = "[201~".bytes

  # How long to wait for the rest of the end marker once its ESC has arrived.
  #
  # Deliberately not ESCAPE_TIMEOUT_MS: that value exists to tell a lone Escape
  # KEYPRESS from a sequence, a distinction a paste has already settled — the
  # terminal opened the bracket and owes us the close. It only has to outlast
  # scheduling jitter on the tail of a transfer (ssh/mosh, a loaded machine),
  # which 50ms does not. Bounded rather than infinite so a terminal that dies
  # mid-paste degrades to delivering the bytes as content instead of hanging.
  PASTE_END_TIMEOUT_MS = 1000

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
  # Whether a PasteStart has been delivered without its matching PasteEnd. The
  # only thing it changes is how ESC is treated: inside a paste ESC is either the
  # start of the literal end marker or content, never a sequence to interpret.
  @in_paste : Bool = false
  # Bytes read while checking for the end marker that turned out not to be it.
  # Bounded by PASTE_END_TAIL.size — the paste body is never accumulated here, so
  # an arbitrarily large transfer still streams a byte at a time.
  @pending = Deque(UInt8).new
  # When the open end-marker probe gives up, and the current call's budget.
  # Waiting the whole marker window inside one `poll_event` would charge a 16ms
  # render loop a full second on a truncated paste; instead each call waits only
  # what it has, hands the ESC back, and the next call resumes the probe.
  @paste_deadline : MonotonicTime? = nil
  @poll_deadline : MonotonicTime? = nil
  # Absolute end-to-end deadline used by every byte of the current parse. A
  # blocking poll may wait indefinitely for its first byte, but once parsing has
  # started, an incomplete sequence is bounded by the escape ambiguity window.
  @parse_deadline : MonotonicTime? = nil

  def initialize(@reader : Reader)
  end

  # Prepares to move ownership to an unparsed raw-input consumer.
  #
  # An open paste is parser state even when its push-back queue is momentarily
  # empty, so raw access must wait until the matching PasteEnd restores a clean
  # boundary. Once that boundary is clean, the raw consumer owns the next byte;
  # discard the protocol echo guard so it cannot affect parsing after handback.
  def prepare_raw_handoff : Bool
    ready = @pending.empty? && !@in_paste && @paste_deadline.nil?
    @dup_guard = nil if ready
    ready
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
    return first_byte.unsafe_chr if first_byte < 0x80 # ASCII fast path

    # Accept the same structural lead-byte range as the old decoder, then apply
    # the RFC 3629 scalar checks after consuming every valid continuation. This
    # preserves recovery: malformed continuations stay unread, while overlong,
    # surrogate, and out-of-range sequences are consumed as one invalid event.
    length, codepoint, minimum = case first_byte
                                 when 0xC0..0xDF then {2, (first_byte & 0x1F).to_i32, 0x80}
                                 when 0xE0..0xEF then {3, (first_byte & 0x0F).to_i32, 0x800}
                                 when 0xF0..0xF7 then {4, (first_byte & 0x07).to_i32, 0x10000}
                                 else                 return
                                 end

    (length - 1).times do
      # Peek + confirm before consuming so a non-continuation byte is left in
      # the buffer rather than swallowed. Every continuation shares the poll's
      # absolute deadline rather than receiving a fresh timeout.
      byte = peek_parse_byte
      return unless byte && (byte & 0xC0) == 0x80
      read_parse_byte
      codepoint = (codepoint << 6) | (byte & 0x3F)
    end

    return unless codepoint >= minimum && valid_codepoint?(codepoint)

    codepoint.unsafe_chr
  end

  # Polls for an input event with optional timeout.
  #
  # - `timeout_ms` - Timeout in milliseconds (-1 for blocking)
  #
  # Returns an Event or nil if timeout/no data.
  def poll_event(timeout_ms : Int32 = -1) : Event::Any?
    now = monotonic_now
    @poll_deadline = timeout_ms < 0 ? nil : now + timeout_ms.milliseconds
    @parse_deadline = @poll_deadline

    # Bytes already taken off the fd while probing for an end marker come first,
    # and without consulting the fd: they have arrived, so no timeout applies.
    if byte = @pending.shift?
      @parse_deadline ||= now + ESCAPE_TIMEOUT_MS.milliseconds
      return parse_byte(byte)
    end

    wait = timeout_ms < 0 ? Int32::MAX : timeout_ms
    byte = @reader.read_byte(wait)
    return unless byte

    # A blocking poll is unbounded only while waiting for its first byte. Once a
    # possible multi-byte event starts, truncated input must not block forever.
    @parse_deadline ||= monotonic_now + ESCAPE_TIMEOUT_MS.milliseconds
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
  #
  # Both 0x0D and 0x0A yield Key::Enter, but they carry the byte that produced
  # them as `char` ('\r' / '\n'). Without bracketed paste a terminal hands a
  # pasted CRLF over as those two bytes back to back, and an application that
  # cannot tell them apart inserts TWO newlines per pasted line. `char` lets a
  # caller collapse the pair; nothing else changes (`Event::Key#char` already
  # fell back to '\n' for Enter, so a caller that ignores it sees no difference
  # on the 0x0A path).
  #
  # That collapse is only available when CR LF actually arrives as CR LF, which is
  # not something a terminal guarantees. Some normalize the LF of a pasted CRLF
  # into a SECOND CR, and CR CR is by definition what pressing Enter twice looks
  # like — no inspection of `char` separates those. `Terminal#enable_bracketed_paste`
  # is the reliable answer: it brackets the run with Key::PasteStart/PasteEnd and
  # stops the translation. These byte paths stay exactly as they are inside a
  # paste — bracketing says where the paste is, it does not normalize what is in it.
  private def parse_byte(byte : UInt8) : Event::Any?
    # Snapshot + clear the one-shot dup guard: it only matches a raw byte that
    # arrives IMMEDIATELY after the CSI-u event that set it (handled in the
    # printable branch below). Any other byte clears it. The escape branch may
    # set a fresh guard for the *next* call.
    dup = @dup_guard
    @dup_guard = nil
    case byte
    when 0x1B # ESC - could be escape key or start of sequence
      @in_paste ? parse_paste_escape : parse_escape_sequence
    when 0x00 # Ctrl+Space or Ctrl+@
      Event::Key.new(Key::Space, Modifier::Ctrl)
    when 0x08 # Backspace (Ctrl+H on some terminals, but treat as Backspace)
      Event::Key.new(Key::Backspace)
    when 0x09 # Tab (technically Ctrl+I, but always treat as Tab)
      Event::Key.new(Key::Tab)
    when 0x0A # Line feed (Ctrl+J) - treat as Enter
      Event::Key.new(Key::Enter, char: '\n')
    when 0x0D # Carriage return (Ctrl+M) - treat as Enter
      Event::Key.new(Key::Enter, char: '\r')
    when 0x01..0x1A # Ctrl+A through Ctrl+Z (excluding special cases above)
      key = Key.from_char(('a'.ord + byte - 1).chr)
      Event::Key.new(key, Modifier::Ctrl)
    when 0x7F # DEL (Backspace on most terminals)
      Event::Key.new(Key::Backspace)
    else
      parse_printable(byte, dup)
    end
  end

  # Handles a printable (non-control) byte: reads the full UTF-8 char and emits
  # a Key event, supporting Hangul, CJK, accented letters, etc. for text input.
  private def parse_printable(byte : UInt8, dup : Char?) : Event::Any
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

  # Parses an escape sequence starting with ESC (0x1B).
  # ESC arriving inside a paste: either it opens the literal end marker, or it is
  # content. Never a sequence to interpret — that route is what loses the marker.
  #
  # The comparison is against raw bytes and waits on PASTE_END_TIMEOUT_MS, so
  # neither escape parsing nor the 50ms Escape-key heuristic can consume them. On
  # a miss every byte taken is handed back in order, so content that merely looks
  # like a marker at first is delivered whole rather than eaten by the probe.
  private def parse_paste_escape : Event::Any?
    @paste_deadline ||= monotonic_now + PASTE_END_TIMEOUT_MS.milliseconds
    tail = read_paste_end_tail
    tail.reverse_each { |b| @pending.unshift(b) }

    # Short of a full marker while the window is still open: this call simply ran
    # out of budget. Put the ESC back too and report no event — the next call
    # re-enters here and keeps waiting, so a short poll interval costs latency
    # rather than the marker.
    if tail.size < PASTE_END_TAIL.size && ms_until(@paste_deadline) > 0
      @pending.unshift(0x1B_u8)
      return nil
    end

    @paste_deadline = nil
    return Event::Key.new(Key::Escape, char: '\e') unless tail == PASTE_END_TAIL

    PASTE_END_TAIL.size.times { @pending.shift }
    @in_paste = false
    Event::Key.new(Key::PasteEnd)
  end

  # Up to PASTE_END_TAIL.size bytes following an in-paste ESC, drawn from the
  # push-back buffer first. Returns fewer only when the stream stalls past
  # PASTE_END_TIMEOUT_MS or ends, which is a truncated paste, not a marker.
  private def read_paste_end_tail : Array(UInt8)
    tail = [] of UInt8

    while tail.size < PASTE_END_TAIL.size
      byte = @pending.shift?
      unless byte
        # Reader consumes buffered bytes even for a zero wait, so a zero-timeout
        # poll can finish a marker that arrived in an earlier buffer fill.
        byte = @reader.read_byte(paste_wait_ms)
        break unless byte
      end
      tail << byte
    end

    tail
  end

  # How long to block for the next marker byte: the shorter of what the caller
  # asked for and what is left of the marker window.
  private def paste_wait_ms : Int32
    window = ms_until(@paste_deadline)
    budget = @poll_deadline ? ms_until(@poll_deadline) : window
    {window, budget}.min
  end

  private def ms_until(deadline : MonotonicTime?) : Int32
    return 0 unless deadline
    ceil_ms((deadline - monotonic_now).total_milliseconds)
  end

  # Rounds *remaining* milliseconds up, kept separate from the clock read above so
  # the rounding itself is testable.
  #
  # Hand-rolled rather than `Float#ceil`: that is the only call in the library that
  # pulls in libm, which the C ABI test links without `-lm`. A fraction must round
  # up — truncating a live deadline to a 0ms wait would spin — but a whole number
  # is already the answer and must not be inflated past the caller's budget.
  private def ceil_ms(remaining : Float64) : Int32
    return 0 if remaining <= 0

    whole = remaining.to_i
    remaining > whole ? whole + 1 : whole
  end

  # Reads or peeks one continuation byte within the current parse's absolute
  # deadline. Reader deliberately checks its internal buffer before the timeout,
  # which keeps zero-timeout polling useful for complete, already-buffered input.
  private def read_parse_byte(max_wait_ms : Int32? = nil) : UInt8?
    @reader.read_byte(parse_wait_ms(max_wait_ms))
  end

  private def peek_parse_byte(max_wait_ms : Int32? = nil) : UInt8?
    @reader.peek_byte(parse_wait_ms(max_wait_ms))
  end

  private def parse_wait_ms(max_wait_ms : Int32?) : Int32
    wait = ms_until(@parse_deadline)
    max_wait_ms ? {wait, max_wait_ms}.min : wait
  end

  private def parse_escape_sequence : Event::Any
    # Check if more data follows (escape sequence) or just ESC key. The Escape
    # ambiguity window may shorten, but never extend, the caller's deadline.
    byte = peek_parse_byte(ESCAPE_TIMEOUT_MS)
    return Event::Key.new(Key::Escape) unless byte

    case byte
    when '['.ord.to_u8 # CSI sequence: \e[...
      read_parse_byte  # consume '['
      parse_csi_sequence
    when 'O'.ord.to_u8 # SS3 sequence: \eO... (F1-F4, some arrows)
      read_parse_byte  # consume 'O'
      parse_ss3_sequence
    else
      # Alt+key: \e followed by printable char (UTF-8 capable)
      read_parse_byte # consume the (first) char byte
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
    first = read_parse_byte
    return Event::Key.new(Key::Unknown) unless first

    # SGR mouse: \e[<...
    return parse_sgr_mouse if first == '<'.ord

    # Normal mouse: \e[M... — must be checked before the final-byte fast path
    # because 'M' (0x4D) is itself inside the 0x40-0x7E final range.
    return parse_normal_mouse if first == 'M'.ord

    # Linux console function keys: \e[[A through \e[[E. The second '[' (0x5B) is
    # itself inside the 0x40-0x7E final range, so it must be handled before the
    # fast path below — otherwise '[' is consumed as a final byte and the
    # trailing key letter is lost.
    return parse_linux_console_key if first == '['.ord

    # Fast path: parameterless CSI keys (\e[A, \e[Z, bare \e[u, \e[~).
    return decode_csi_key(Bytes.empty, first.unsafe_chr) if 0x40 <= first <= 0x7E

    parse_csi_params(first)
  end

  private def parse_linux_console_key : Event::Key
    final = read_parse_byte
    return Event::Key.new(Key::Unknown) unless final

    # Avoid constructing a lookup String for this fixed five-key alphabet.
    key = case final
          when 'A'.ord then Key::F1
          when 'B'.ord then Key::F2
          when 'C'.ord then Key::F3
          when 'D'.ord then Key::F4
          when 'E'.ord then Key::F5
          else              Key::Unknown
          end
    Event::Key.new(key)
  end

  private def parse_csi_params(first : UInt8) : Event::Any
    # CSI parameters are bounded and only needed for this call, so keep their
    # raw bytes on the stack. `accounted` deliberately mirrors the old Builder's
    # UTF-8 byte count: bytes >= 0x80 expanded to two bytes there. SGR mouse has
    # always counted raw bytes instead (see parse_sgr_mouse).
    buffer = uninitialized UInt8[MAX_SEQUENCE_LENGTH]
    length = 1
    accounted = first < 0x80 ? 1 : 2
    buffer[0] = first

    while byte = read_parse_byte
      if 0x40 <= byte <= 0x7E
        return decode_csi_key(buffer.to_slice[0, length], byte.unsafe_chr)
      end

      # `accounted >= length` guarantees this write remains within the fixed
      # buffer. The byte that reaches the historical limit is consumed, while
      # the following final byte remains available as the next event.
      buffer[length] = byte
      length += 1
      accounted += byte < 0x80 ? 1 : 2
      if accounted >= MAX_SEQUENCE_LENGTH
        Log.warn { "CSI sequence too long, aborting" }
        return Event::Key.new(Key::Unknown)
      end
    end

    Event::Key.new(Key::Unknown)
  end

  # Decodes a CSI sequence directly from its bounded stack bytes.
  private def decode_csi_key(params : Bytes, final : Char) : Event::Any
    if final == 'u'
      return parse_kitty_key(params)
    end

    modifiers = parse_modifiers(params)

    if final == '~'
      first_end = index_of(params, ';'.ord.to_u8)
      code = parse_decimal(params, 0, first_end) || 0

      # modifyOtherKeys requires at least three semicolon-separated fields.
      second_end = first_end < params.size ? index_of(params, ';'.ord.to_u8, first_end + 1) : params.size
      if code == 27 && second_end < params.size
        return parse_modify_other_keys(params, first_end + 1, second_end)
      end

      # PASTE_KEYS is consulted after TILDE_KEYS so the keys people actually
      # press stay a single lookup; 200/201 would otherwise fall through to
      # Key::Unknown and be indistinguishable from each other.
      key = TILDE_KEYS[code]? || PASTE_KEYS[code]? || Key::Unknown
      @in_paste = true if key.paste_start?
      @in_paste = false if key.paste_end?
      return Event::Key.new(key, modifiers)
    end

    # Standard CSI key lookup — the hot path (arrows, Home/End, F1-F4, BackTab).
    if key = CSI_KEYS[final]?
      return Event::Key.new(key, modifiers)
    end

    Event::Key.new(Key::Unknown, modifiers)
  end

  # Parses Kitty keyboard fields without materializing parameter Strings or
  # Arrays. Only a pure-text Preedit event receives an owned String.
  private def parse_kitty_key(params : Bytes) : Event::Any
    first_end = index_of(params, ';'.ord.to_u8)
    code_end = index_of(params, ':'.ord.to_u8, 0, first_end)
    codepoint = parse_decimal(params, 0, code_end) || 0

    second_start = first_end < params.size ? first_end + 1 : params.size
    second_end = index_of(params, ';'.ord.to_u8, second_start)
    mod_end = index_of(params, ':'.ord.to_u8, second_start, second_end)
    mod_code = parse_decimal(params, second_start, mod_end) || 1
    modifiers = Modifier.from_xterm_code(mod_code)

    text_start = second_end < params.size ? second_end + 1 : params.size
    text_end = index_of(params, ';'.ord.to_u8, text_start)

    if codepoint == 0
      # Empty text means "preedit cleared" and remains an observable event.
      @protocol_active = true
      return Event::Preedit.new(build_text_from_codepoints(params, text_start, text_end))
    end

    # Prefer the first valid associated-text codepoint for the inserted char.
    c = first_text_codepoint(params, text_start, text_end) ||
        (valid_codepoint?(codepoint) ? codepoint.unsafe_chr : nil)
    @protocol_active = true if producing_text?(c)

    key = codepoint_to_key(codepoint)
    @dup_guard = c if echoable_text?(c, modifiers)
    Event::Key.new(key, modifiers, char: c)
  end

  # Whether `c` is a text-producing printable char (printable and not a control
  # codepoint). Used to gate Kitty text-protocol dedup state.
  private def producing_text?(c : Char?) : Bool
    return false unless c
    c.printable? && c.ord >= 32
  end

  # Whether this CSI-u report is one the terminal might ALSO echo as a raw byte —
  # the only case the dup guard exists for.
  #
  # Ctrl/Alt/Meta-modified keys never are: a terminal sends Ctrl+P as the control
  # byte 0x10, never as a raw 'p'. But `c` falls back to the CODEPOINT when the
  # text field is empty, so Ctrl+P yields c == 'p' and gating on producing_text?
  # alone armed the guard with 'p' — swallowing the very next plain 'p' the user
  # typed. Shift+letter and IME commits (which DO carry text and DO get echoed)
  # are unaffected, since they carry no Ctrl/Alt/Meta.
  private def echoable_text?(c : Char?, modifiers : Modifier) : Bool
    return false unless producing_text?(c)
    !(modifiers.ctrl? || modifiers.alt? || modifiers.meta?)
  end

  # Parses modifyOtherKeys: CSI 27 ; modifier ; keycode ~.
  private def parse_modify_other_keys(params : Bytes, mod_start : Int32, mod_end : Int32) : Event::Key
    key_start = mod_end + 1
    key_end = index_of(params, ';'.ord.to_u8, key_start)
    mod_code = parse_decimal(params, mod_start, mod_end) || 1
    keycode = parse_decimal(params, key_start, key_end) || 0

    modifiers = Modifier.from_xterm_code(mod_code)
    key = codepoint_to_key(keycode)
    c = (keycode > 0 && valid_codepoint?(keycode)) ? keycode.unsafe_chr : nil

    if producing_text?(c)
      @protocol_active = true
      @dup_guard = c if echoable_text?(c, modifiers)
    end

    Event::Key.new(key, modifiers, char: c)
  end

  # Whether `cp` is a scalar Unicode codepoint that maps to a real Char: in
  # range and not a UTF-16 surrogate (U+D800..U+DFFF).
  private def valid_codepoint?(cp : Int32) : Bool
    cp >= 0 && cp <= Char::MAX_CODEPOINT && !(0xD800..0xDFFF).includes?(cp)
  end

  private def first_text_codepoint(params : Bytes, start : Int32, limit : Int32) : Char?
    field_start = start
    while field_start < limit
      field_end = index_of(params, ':'.ord.to_u8, field_start, limit)
      if codepoint = parse_decimal(params, field_start, field_end)
        return codepoint.unsafe_chr if valid_codepoint?(codepoint)
      end
      field_start = field_end + 1
    end
    nil
  end

  # Builds exactly one owned String for Preedit text. Every scalar's UTF-8
  # encoding is no longer than its decimal field, so the bounded CSI capacity
  # also bounds this stack buffer. Invalid fields are skipped as before.
  private def build_text_from_codepoints(params : Bytes, start : Int32, limit : Int32) : String
    buffer = uninitialized UInt8[MAX_SEQUENCE_LENGTH]
    bytesize = 0
    char_count = 0
    field_start = start
    while field_start < limit
      field_end = index_of(params, ':'.ord.to_u8, field_start, limit)
      if codepoint = parse_decimal(params, field_start, field_end)
        if valid_codepoint?(codepoint)
          size = utf8_size(codepoint)
          return "" if bytesize > MAX_SEQUENCE_LENGTH - size
          bytesize += write_utf8(buffer.to_unsafe + bytesize, codepoint)
          char_count += 1
        end
      end
      field_start = field_end + 1
    end

    String.new(buffer.to_unsafe, bytesize, char_count)
  end

  private def utf8_size(codepoint : Int32) : Int32
    return 1 if codepoint <= 0x7F
    return 2 if codepoint <= 0x7FF
    return 3 if codepoint <= 0xFFFF
    4
  end

  private def write_utf8(buffer : UInt8*, codepoint : Int32) : Int32
    case codepoint
    when ..0x7F
      buffer[0] = codepoint.to_u8
      1
    when ..0x7FF
      buffer[0] = (0xC0 | (codepoint >> 6)).to_u8
      buffer[1] = (0x80 | (codepoint & 0x3F)).to_u8
      2
    when ..0xFFFF
      buffer[0] = (0xE0 | (codepoint >> 12)).to_u8
      buffer[1] = (0x80 | ((codepoint >> 6) & 0x3F)).to_u8
      buffer[2] = (0x80 | (codepoint & 0x3F)).to_u8
      3
    else
      buffer[0] = (0xF0 | (codepoint >> 18)).to_u8
      buffer[1] = (0x80 | ((codepoint >> 12) & 0x3F)).to_u8
      buffer[2] = (0x80 | ((codepoint >> 6) & 0x3F)).to_u8
      buffer[3] = (0x80 | (codepoint & 0x3F)).to_u8
      4
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

  # Parses modifier code from CSI params: "1;2" means modifier code 2.
  private def parse_modifiers(params : Bytes) : Modifier
    first_end = index_of(params, ';'.ord.to_u8)
    return Modifier::None if first_end == params.size

    second_start = first_end + 1
    second_end = index_of(params, ';'.ord.to_u8, second_start)
    mod_code = parse_decimal(params, second_start, second_end) || 1
    Modifier.from_xterm_code(mod_code)
  end

  private def index_of(bytes : Bytes, value : UInt8, start : Int32 = 0, limit : Int32 = bytes.size) : Int32
    index = start
    while index < limit
      return index if bytes[index] == value
      index += 1
    end
    limit
  end

  # Allocation-free equivalent of String#to_i? for the Latin-1 characters the
  # old generic-CSI Builder produced. SGR passes `raw_utf8: true` because its
  # former String retained raw bytes instead; this distinction is observable on
  # malformed fields. Signed Int32 overflow is rejected before multiplication.
  private def parse_decimal(bytes : Bytes, start : Int32, limit : Int32,
                            raw_utf8 : Bool = false) : Int32?
    index = skip_decimal_whitespace(bytes, start, limit, raw_utf8)
    return if index >= limit

    negative = bytes[index] == '-'.ord
    index += 1 if negative || bytes[index] == '+'.ord
    maximum = negative ? 2_147_483_648_u64 : 2_147_483_647_u64
    value, finish = scan_decimal_digits(bytes, index, limit, maximum) || return
    return unless decimal_terminated?(bytes, start, finish, limit, raw_utf8)

    if negative
      return Int32::MIN if value == 2_147_483_648_u64
      -value.to_i32
    else
      value.to_i32
    end
  end

  private def skip_decimal_whitespace(bytes : Bytes, start : Int32, limit : Int32,
                                      raw_utf8 : Bool) : Int32
    index = start
    while index < limit
      size = decimal_whitespace_size(bytes, index, limit, raw_utf8)
      break if size == 0
      index += size
    end
    index
  end

  private def decimal_whitespace_size(bytes : Bytes, index : Int32, limit : Int32,
                                      raw_utf8 : Bool) : Int32
    return bytes[index].unsafe_chr.whitespace? ? 1 : 0 unless raw_utf8

    codepoint, size = decode_utf8_at(bytes, index, limit) || return 0
    codepoint.unsafe_chr.whitespace? ? size : 0
  end

  private def decode_utf8_at(bytes : Bytes, index : Int32, limit : Int32) : {Int32, Int32}?
    first = bytes[index]
    return {first.to_i32, 1} if first < 0x80

    size, codepoint, minimum = case first
                               when 0xC0..0xDF then {2, (first & 0x1F).to_i32, 0x80}
                               when 0xE0..0xEF then {3, (first & 0x0F).to_i32, 0x800}
                               when 0xF0..0xF7 then {4, (first & 0x07).to_i32, 0x10000}
                               else                 return
                               end
    return if size > limit - index

    (1...size).each do |offset|
      byte = bytes[index + offset]
      return unless (byte & 0xC0) == 0x80
      codepoint = (codepoint << 6) | (byte & 0x3F)
    end
    return unless codepoint >= minimum && valid_codepoint?(codepoint)

    {codepoint, size}
  end

  private def scan_decimal_digits(bytes : Bytes, start : Int32, limit : Int32,
                                  maximum : UInt64) : {UInt64, Int32}?
    index = start
    value = 0_u64
    while index < limit
      byte = bytes[index]
      break unless '0'.ord <= byte <= '9'.ord

      digit = (byte - '0'.ord).to_u64
      return if value > (maximum - digit) // 10
      value = value * 10 + digit
      index += 1
    end
    return if index == start

    {value, index}
  end

  private def decimal_terminated?(bytes : Bytes, start : Int32, finish : Int32, limit : Int32,
                                  raw_utf8 : Bool) : Bool
    return true if finish == limit || bytes[finish] == 0
    return skip_decimal_whitespace(bytes, finish, limit, true) == limit if raw_utf8

    # Generic CSI formerly encoded each input byte as its Latin-1 codepoint in a
    # Builder. Preserve String#to_i?'s byte-pointer behavior around malformed
    # embedded NULs without materializing that UTF-8 String.
    pointer = encoded_bytesize(bytes, start, finish)
    trailing = limit
    while trailing > start && bytes[trailing - 1].unsafe_chr.whitespace?
      trailing -= 1
    end
    pointer += encoded_bytesize(bytes, trailing, limit)
    encoded_byte_at(bytes, start, limit, pointer) == 0
  end

  private def encoded_bytesize(bytes : Bytes, start : Int32, limit : Int32) : Int32
    size = 0
    index = start
    while index < limit
      size += bytes[index] < 0x80 ? 1 : 2
      index += 1
    end
    size
  end

  private def encoded_byte_at(bytes : Bytes, start : Int32, limit : Int32, offset : Int32) : UInt8
    position = 0
    index = start
    while index < limit
      byte = bytes[index]
      if byte < 0x80
        return byte if position == offset
        position += 1
      else
        return (0xC0 | (byte >> 6)).to_u8 if position == offset
        return (0x80 | (byte & 0x3F)).to_u8 if position + 1 == offset
        position += 2
      end
      index += 1
    end
    0_u8
  end

  # Parses an SS3 sequence: \eO...
  #
  # SS3 sequences are used for F1-F4 and some arrow keys.
  private def parse_ss3_sequence : Event::Any
    byte = read_parse_byte
    unless byte
      return Event::Key.new(Key::Unknown)
    end

    key = SS3_KEYS[byte.chr]? || Key::Unknown
    Event::Key.new(key)
  end

  # Parses SGR extended mouse protocol (mode 1006).
  # Format: \e[<Cb;Cx;CyM (press) or \e[<Cb;Cx;Cym (release)
  private def parse_sgr_mouse : Event::Any
    # Unlike generic CSI accounting, the historical SGR limit counts raw bytes.
    buffer = uninitialized UInt8[MAX_SEQUENCE_LENGTH]
    length = 0

    while byte = read_parse_byte
      if byte == 'M'.ord || byte == 'm'.ord
        event = parse_sgr_params_to_event(buffer.to_slice[0, length], byte == 'm'.ord)
        return event || Event::Key.new(Key::Unknown)
      end

      buffer[length] = byte
      length += 1
      if length >= MAX_SEQUENCE_LENGTH
        Log.warn { "SGR mouse sequence too long" }
        return Event::Key.new(Key::Unknown)
      end
    end

    Event::Key.new(Key::Unknown)
  end

  private def parse_sgr_params_to_event(params : Bytes, is_release : Bool) : Event::Mouse?
    first_end = index_of(params, ';'.ord.to_u8)
    return if first_end == params.size
    second_end = index_of(params, ';'.ord.to_u8, first_end + 1)
    return if second_end == params.size
    third_end = index_of(params, ';'.ord.to_u8, second_end + 1)

    cb = parse_decimal(params, 0, first_end, raw_utf8: true) || return
    x = parse_decimal(params, first_end + 1, second_end, raw_utf8: true) || return
    y = parse_decimal(params, second_end + 1, third_end, raw_utf8: true) || return

    button = Event::Mouse::Button.from_cb(cb)
    # Wheel events are instantaneous - they don't have release events.
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
    cb_byte = read_parse_byte
    cx_byte = read_parse_byte
    cy_byte = read_parse_byte

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
