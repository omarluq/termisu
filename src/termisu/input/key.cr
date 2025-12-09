# Key enum representing all keyboard keys.
#
# Each key has its own enum value for type-safe key handling.
# Modifiers (Ctrl, Alt, Shift) are tracked separately in the Modifier flags.
#
# Example:
# ```
# event = termisu.poll_event
# if event.is_a?(Termisu::Event::Key)
#   case event.key
#   when .escape?  then puts "Escape pressed"
#   when .enter?   then puts "Enter pressed"
#   when .lower_a? then puts "a pressed"
#   when .upper_a? then puts "A pressed"
#   end
# end
# ```
enum Termisu::Input::Key
  # Letters (uppercase A-Z)
  UpperA
  UpperB
  UpperC
  UpperD
  UpperE
  UpperF
  UpperG
  UpperH
  UpperI
  UpperJ
  UpperK
  UpperL
  UpperM
  UpperN
  UpperO
  UpperP
  UpperQ
  UpperR
  UpperS
  UpperT
  UpperU
  UpperV
  UpperW
  UpperX
  UpperY
  UpperZ

  # Letters (lowercase a-z)
  LowerA
  LowerB
  LowerC
  LowerD
  LowerE
  LowerF
  LowerG
  LowerH
  LowerI
  LowerJ
  LowerK
  LowerL
  LowerM
  LowerN
  LowerO
  LowerP
  LowerQ
  LowerR
  LowerS
  LowerT
  LowerU
  LowerV
  LowerW
  LowerX
  LowerY
  LowerZ

  # Numbers 0-9
  Num0
  Num1
  Num2
  Num3
  Num4
  Num5
  Num6
  Num7
  Num8
  Num9

  # Punctuation & Symbols (unshifted)
  Backtick     # `
  Minus        # -
  Equals       # =
  LeftBracket  # [
  RightBracket # ]
  Backslash    # \
  Semicolon    # ;
  Quote        # '
  Comma        # ,
  Period       # .
  Slash        # /

  # Shifted symbols
  Tilde       # ~
  Exclaim     # !
  At          # @
  Hash        # #
  Dollar      # $
  Percent     # %
  Caret       # ^
  Ampersand   # &
  Asterisk    # *
  LeftParen   # (
  RightParen  # )
  Underscore  # _
  Plus        # +
  LeftBrace   # {
  RightBrace  # }
  Pipe        # |
  Colon       # :
  DoubleQuote # "
  LessThan    # <
  GreaterThan # >
  Question    # ?

  # Whitespace & Control
  Space
  Tab
  Enter
  Backspace
  Escape

  # Arrow keys
  Up
  Down
  Left
  Right

  # Navigation
  Home
  End
  PageUp
  PageDown
  Insert
  Delete

  # Function keys (F1-F24)
  F1
  F2
  F3
  F4
  F5
  F6
  F7
  F8
  F9
  F10
  F11
  F12
  F13
  F14
  F15
  F16
  F17
  F18
  F19
  F20
  F21
  F22
  F23
  F24

  # Special / Modifier keys (only detectable with enhanced keyboard protocols)
  CapsLock
  ScrollLock
  NumLock
  PrintScreen
  Pause
  BackTab # Shift+Tab
  Unknown # Unrecognized sequence

  # Creates a Key from a printable character.
  #
  # Maps ASCII characters to their corresponding Key enum values.
  # Returns Key::Unknown for unmapped characters.
  def self.from_char(c : Char) : Key
    case c
    when 'A'..'Z'   then Key.new(c.ord - 'A'.ord)      # UpperA..UpperZ
    when 'a'..'z'   then Key.new(26 + c.ord - 'a'.ord) # LowerA..LowerZ
    when '0'..'9'   then Key.new(52 + c.ord - '0'.ord) # Num0..Num9
    when '\r', '\n' then Enter
    else
      KeySymbolMaps.char_to_key[c]? || Unknown
    end
  end

  # Returns the character representation of this key, if printable.
  def to_char : Char?
    if UpperA.value <= self.value <= UpperZ.value
      ('A'.ord + (self.value - UpperA.value)).chr
    elsif LowerA.value <= self.value <= LowerZ.value
      ('a'.ord + (self.value - LowerA.value)).chr
    elsif Num0.value <= self.value <= Num9.value
      ('0'.ord + (self.value - Num0.value)).chr
    else
      KeySymbolMaps.key_to_char[self]?
    end
  end

  # Returns true if this is a letter key (A-Z or a-z).
  def letter? : Bool
    (UpperA.value <= self.value <= UpperZ.value) ||
      (LowerA.value <= self.value <= LowerZ.value)
  end

  # Returns true if this is a digit key (0-9).
  def digit? : Bool
    Num0.value <= self.value <= Num9.value
  end

  # Returns true if this is a function key (F1-F24).
  def function_key? : Bool
    F1.value <= self.value <= F24.value
  end

  # Returns true if this is a navigation key.
  def navigation? : Bool
    self.in?(Up, Down, Left, Right, Home, End, PageUp, PageDown)
  end

  # Returns true if this key produces a printable character.
  def printable? : Bool
    !to_char.nil?
  end
end

# Symbol lookup tables for Key enum.
# Defines the single source of truth for symbol <-> key mappings.
# Uses lazy initialization with class variables to avoid enum constant limitations.
module Termisu::Input::KeySymbolMaps
  # Char to Key lookup hash - single source of truth for symbol mappings.
  def self.char_to_key : Hash(Char, Key)
    @@char_to_key ||= build_char_to_key_map
  end

  # Key to Char lookup hash - derived from char_to_key for DRY.
  def self.key_to_char : Hash(Key, Char)
    @@key_to_char ||= char_to_key.invert.tap { |map| map[Key::Enter] = '\n' }
  end

  # Builds the char-to-key mapping hash.
  private def self.build_char_to_key_map : Hash(Char, Key)
    {
      '`'  => Key::Backtick,
      '-'  => Key::Minus,
      '='  => Key::Equals,
      '['  => Key::LeftBracket,
      ']'  => Key::RightBracket,
      '\\' => Key::Backslash,
      ';'  => Key::Semicolon,
      '\'' => Key::Quote,
      ','  => Key::Comma,
      '.'  => Key::Period,
      '/'  => Key::Slash,
      '~'  => Key::Tilde,
      '!'  => Key::Exclaim,
      '@'  => Key::At,
      '#'  => Key::Hash,
      '$'  => Key::Dollar,
      '%'  => Key::Percent,
      '^'  => Key::Caret,
      '&'  => Key::Ampersand,
      '*'  => Key::Asterisk,
      '('  => Key::LeftParen,
      ')'  => Key::RightParen,
      '_'  => Key::Underscore,
      '+'  => Key::Plus,
      '{'  => Key::LeftBrace,
      '}'  => Key::RightBrace,
      '|'  => Key::Pipe,
      ':'  => Key::Colon,
      '"'  => Key::DoubleQuote,
      '<'  => Key::LessThan,
      '>'  => Key::GreaterThan,
      '?'  => Key::Question,
      ' '  => Key::Space,
      '\t' => Key::Tab,
    }
  end

  @@char_to_key : Hash(Char, Key)?
  @@key_to_char : Hash(Key, Char)?
end
