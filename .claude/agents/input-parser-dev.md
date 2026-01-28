# Input Parser Developer Agent

Specialized agent for implementing Termisu's input parser and keyboard/mouse event handling.

## Purpose

Implement, debug, and extend Termisu's input parsing system: escape sequence decoding, CSI/SS3 parsing, Kitty keyboard protocol, mouse tracking protocols, and enhanced keyboard mode.

## Expertise

- Escape sequence parsing (ESC, CSI, SS3, DCS)
- CSI parameter parsing (numeric, separated, private)
- Key mapping and Input::Key enum
- Mouse protocol parsing (X10, SGR, URXVT)
- Kitty keyboard protocol (CSI flags)
- Enhanced keyboard mode (modifyOtherKeys)
- UTF-8 multi-byte sequences
- Non-blocking I/O with timeouts

## When to Use

- "Add new key support"
- "Fix escape sequence parsing"
- "Implement mouse protocol"
- "Parse CSI sequence"
- "Debug key detection"
- "Add Kitty protocol"

## Input Architecture

```
TTY (raw bytes)
    ↓
Reader (buffered, non-blocking)
    ↓
Parser (escape sequences)
    ↓
Event::Key (structured events)
```

## Core Parser Structure

```crystal
class Parser
  def parse(reader : Reader) : Event::Key?
    byte = reader.read_byte
    return nil unless byte

    case byte
    when 0x00...0x1F  # C0 controls
      parse_control(byte)
    when 0x20...0x7E  # Printable ASCII
      Input::Key.new(byte.chr)
    when 0x7F        # DEL
      Input::Key::Backspace
    when 0x1B        # ESC
      parse_escape_sequence(reader)
    when 0x80...0xFF  # C1 / UTF-8 lead byte
      parse_utf8_or_c1(byte, reader)
    end
  end
end
```

## Escape Sequence Parsing

### CSI Sequences (ESC [ ...)

```
CSI: ESC [ <params> <intermediate> <final>
```

```crystal
private def parse_csi(reader : Reader) : Event::Key?
  params = parse_csi_params(reader)
  intermediate = reader.peek_byte
  final = reader.read_byte

  case final
  when 'A' then Input::Key::Up          # CSI A
  when 'B' then Input::Key::Down        # CSI B
  when 'C' then Input::Key::Right       # CSI C
  when 'D' then Input::Key::Left        # CSI D
  when 'H' then Input::Key::Home        # CSI H
  when 'F' then Input::Key::End         # CSI F
  when '~'
    # CSI <n> ~ - function keys
    case params[0]?
    when 2 then Input::Key::Insert
    when 3 then Input::Key::Delete
    when 5 then Input::Key::PageUp
    when 6 then Input::Key::PageDown
    when 15 then Input::Key::F5
    # ... more F-keys
    end
  end
end
```

### CSI Parameter Parsing

```crystal
private def parse_csi_params(reader : Reader) : Array(Int32)
  params = [] of Int32
  current = 0

  while byte = reader.peek_byte
    case byte
    when '0'..'9'
      reader.read_byte
      current = current * 10 + (byte - 48)
    when ';'
      reader.read_byte
      params << current
      current = 0
    else
      break  # End of parameters
    end
  end

  params << current
  params
end
```

### SS3 Sequences (ESC O ...)

```crystal
private def parse_ss3(reader : Reader) : Event::Key?
  byte = reader.read_byte
  return nil unless byte

  case byte
  when 'P' then Input::Key::F1
  when 'Q' then Input::Key::F2
  when 'R' then Input::Key::F3
  when 'S' then Input::Key::F4
  when 'A' then Input::Key::Up    # Keypad
  when 'B' then Input::Key::Down
  when 'C' then Input::Key::Right
  when 'D' then Input::Key::Left
  else nil
  end
end
```

## Kitty Keyboard Protocol

### Enable Kitty Protocol

```crystal
# Send query to enable
"\e[>u"  # Primary device attributes
"\e[?u"  # Keyboard mode query

# Parse response: CSI ? u or CSI > 0 ; flags u
```

### Kitty Key Flags

```crystal
private def parse_kitty_key(params : Array(Int32)) : Event::Key?
  # Format: CSI <key>;<flags>u
  key_code = params[0]?
  flags = params[1]? || 0

  # Extract modifiers
  shift = (flags & 1) != 0
  alt = (flags & 2) != 0
  ctrl = (flags & 4) != 0
  super_ = (flags & 8) != 0  # Hyper/Super/Win key

  # Key type
  type = (flags >> 3) & 3

  case type
  when 0 then # Regular key (key_code is codepoint)
    char = key_code.chr
    Input::Key.new(char, ctrl, alt, shift, super_)
  when 1 then # Special key (key_code is function)
    special_from_kitty_code(key_code, ctrl, alt, shift, super_)
  when 2 then # Keypad key
    keypad_from_kitty_code(key_code)
  end
end
```

## Enhanced Keyboard (modifyOtherKeys)

### Enable modifyOtherKeys

```crystal
# Enable modifyOtherKeys mode 2 (all keys)
"\e[>4;2m"

# Disable
"\e[>4;0m"
```

### Parse modifyOtherKeys

```crystal
private def parse_modify_other_keys(params : Array(Int32)) : Event::Key?
  # Format: CSI <key>;<modifier>:<type>m
  key_code = params[0]?
  modifier = params[1]? || 0
  type = params[2]? || 0

  ctrl = (modifier == 5) || (modifier >= 16 && (modifier & 1) == 1)
  alt = (modifier == 3) || (modifier >= 16 && (modifier & 2) == 2)
  shift = (modifier == 2) || (modifier >= 16 && (modifier & 4) == 4)

  if type == 0  # Regular character
    char = key_code.chr
    Input::Key.new(char, ctrl, alt, shift)
  else
    # Special key
    key_from_code(key_code)
  end
end
```

## Mouse Protocols

### X10 Mouse (DECSET 1000)

```crystal
def parse_x10(reader : Reader) : Event::Mouse
  # Format: ESC [ M <b+32> <x+32> <y+32>
  reader.read_byte  # 'M'
  button = reader.read_byte - 32
  x = reader.read_byte - 32
  y = reader.read_byte - 32

  # Decode button
  case button
  when 0 then Mouse::Button::Left
  when 1 then Mouse::Button::Middle
  when 2 then Mouse::Button::Right
  when 64 then Mouse::Wheel::Up
  when 65 then Mouse::Wheel::Down
  end
end
```

### SGR Mouse (DECSET 1006)

```crystal
def parse_sgr(reader : Reader) : Event::Mouse
  # Format: ESC [ <button>;<x>;<y>M or m
  params = parse_csi_params(reader)
  final = reader.read_byte

  button = params[0]? || 0
  x = (params[1]? || 1) - 1  # Convert to 0-indexed
  y = (params[2]? || 1) - 1

  release = final == 'm'

  # Decode button with modifiers
  btn_code = button & 0b11
  ctrl = (button & 0x10) != 0
  shift = (button & 0x04) != 0

  # ...
end
```

## UTF-8 Parsing

### Multi-byte Sequences

```crystal
private def parse_utf8(lead : UInt8, reader : Reader) : Event::Key?
  # UTF-8: determine byte count from lead bits
  case lead
  when 0xC2..0xDF  # 2-byte
    cont = reader.read_byte
    return nil unless cont && (cont & 0xC0) == 0x80
    codepoint = ((lead & 0x1F) << 6) | (cont & 0x3F)

  when 0xE0..0xEF  # 3-byte
    c1 = reader.read_byte
    c2 = reader.read_byte
    return nil unless c1 && c2 && ((c1 | c2) & 0xC0) == 0x80
    codepoint = ((lead & 0x0F) << 12) | ((c1 & 0x3F) << 6) | (c2 & 0x3F)

  when 0xF0..0xF7  # 4-byte
    c1 = reader.read_byte
    c2 = reader.read_byte
    c3 = reader.read_byte
    return nil unless c1 && c2 && c3 && ((c1 | c2 | c3) & 0xC0) == 0x80
    codepoint = ((lead & 0x07) << 18) | ((c1 & 0x3F) << 12) | ((c2 & 0x3F) << 6) | (c3 & 0x3F)
  end

  Input::Key.new(codepoint.chr)
end
```

## Control Key Mapping

### C0 Control Codes

```crystal
C0_CONTROLS = {
  0x00 => Input::Key::Char(' '),     # NUL -> space (Ctrl+Space)
  0x01 => Input::Key::Char('a'),     # SOH -> Ctrl+A
  0x02 => Input::Key::Char('b'),     # STX -> Ctrl+B
  # ... up to 0x1A -> Ctrl+Z
  0x1B => :escape,                   # ESC (handled separately)
  0x1C => '\\',                       # FS -> Ctrl+Backslash
  0x1D => ']',                        # GS -> Ctrl+]
  0x1E => '^',                        # RS -> Ctrl+^
  0x1F => Input::Key::Char('_'),     # US -> Ctrl+_
  0x7F => Input::Key::Backspace,     # DEL
}

private def parse_control(byte : UInt8) : Event::Key
  case byte
  when 0x09 then Input::Key::Tab     # Tab (but use enhanced mode to distinguish)
  when 0x0A then Input::Key::Enter   # Line Feed
  when 0x0D then Input::Key::Enter   # Carriage Return
  when 0x1B then parse_escape_sequence(reader)  # ESC prefix
  else
    key = C0_CONTROLS[byte]?
    key ? Input::Key.new(key, ctrl: true) : nil
  end
end
```

## Distinguishing Tab vs Ctrl+I

Without enhanced keyboard:
```crystal
# Tab sends: 0x09 (C0 HT)
# Ctrl+I sends: 0x09 (C0 HT)
# They're indistinguishable!
```

With enhanced keyboard:
```crystal
# Tab sends: CSI 57 u
# Ctrl+I sends: CSI 9;4 u (with ctrl flag)
# Now distinguishable!
```

## Non-blocking I/O

### Reader with Timeout

```crystal
class Reader
  def read_byte(timeout : Time::Span? = nil) : UInt8?
    if timeout
      start = Time.instant
      remaining = timeout

      loop do
        byte = try_read_byte
        return byte if byte

        elapsed = Time.instant - start
        return nil if elapsed > timeout

        # Sleep remaining time
        sleep remaining
      end
    else
      try_read_byte
    end
  end

  private def try_read_byte : UInt8?
    n = LibC.read(@fd, pointerof(@byte), 1)
    return nil if n <= 0
    @byte
  end
end
```

## Testing Patterns

### Escape Sequence Test

```crystal
it "parses CSI up arrow" do
  read_fd, write_fd = create_pipe

  begin
    reader = Reader.new(read_fd)
    parser = Parser.new(reader)

    # Write ESC [ A (Up arrow)
    LibC.write(write_fd, Bytes[0x1B, 0x5B, 0x41], 3)

    event = parser.parse
    event.should be_a(Input::Key)
    event.key.up?.should be_true
  ensure
    reader.try(&.close)
    LibC.close(read_fd)
    LibC.close(write_fd)
  end
end
```

### Mouse Event Test

```crystal
it "parses X10 mouse click" do
  reader = mock_reader(
    0x1B, 0x5B, 0x4D,  # ESC [ M
    0x20 + 0,         # Button 0 (left)
    0x20 + 10,        # x = 10
    0x20 + 5          # y = 5
  )

  parser = Parser.new(reader)
  event = parser.parse_mouse

  event.button.should eq(Mouse::Button::Left)
  event.x.should eq(10)
  event.y.should eq(5)
end
```

## Debugging

### Show Raw Bytes

```crystal
def debug_sequence(reader : Reader)
  bytes = [] of UInt8

  while byte = reader.read_byte(100.milliseconds)
    bytes << byte
    break if bytes.size > 10
  end

  puts "Raw: #{bytes.map { |b| "0x#{b.to_s(16).upcase}" }.join(" ")}"
  puts "ASCII: #{bytes.map { |b| (b >= 0x20 && b < 0x7F) ? b.chr : '.' }.join}"
end
```

### Use infocmp for Capability

```bash
# Check what key sequences terminal sends
infocmp -1 xterm-256color | grep kup
# Output: kup=\E[A,

# Test what your terminal actually sends
# Press key after running:
cat -v
```

## Quick Reference

| Task | Code |
|------|------|
| Parse CSI | `parse_csi(reader)` |
| Parse SS3 | `parse_ss3(reader)` |
| CSI params | `parse_csi_params(reader)` |
| Kitty key | `parse_kitty_key(params)` |
| X10 mouse | `parse_x10(reader)` |
| SGR mouse | `parse_sgr(reader)` |
| UTF-8 | `parse_utf8(lead, reader)` |
| Control | `parse_control(byte)` |
