# Unicode width calculation for terminal display.
#
# This module implements Unicode Annex #11 (East Asian Width) to determine
# the display column width of characters and grapheme clusters.
#
# Based on Markus Kuhn's wcwidth.c reference implementation and Unicode 15.
#
# ## Width Values
#
# - `0`: Combining marks, control characters, non-printable
# - `1`: Narrow characters (Latin, Greek, Cyrillic, most symbols)
# - `2`: Wide characters (CJK, fullwidth forms, emoji)
#
# ## Ambiguous Width Characters
#
# East Asian Ambiguous characters default to width `1` for consistency
# across terminals. See `AMBIGUOUS_WIDTH` policy constant.
module Termisu::UnicodeWidth
  # Policy for East Asian Ambiguous width characters.
  # These characters can render as width 1 or 2 depending on terminal/font.
  # We default to 1 for stable cross-terminal behavior.
  AMBIGUOUS_WIDTH = 1u8

  # Returns the display width of a single Unicode codepoint.
  #
  # Parameters:
  # - `cp`: Unicode codepoint as Int32
  #
  # Returns `0`, `1`, or `2` for display columns.
  #
  # ```
  # UnicodeWidth.codepoint_width('A'.ord) # => 1
  # UnicodeWidth.codepoint_width('中'.ord) # => 2
  # UnicodeWidth.codepoint_width(0x0301)  # => 0 (combining acute)
  # ```
  def self.codepoint_width(cp : Int32) : UInt8
    return 0u8 if zero_width_codepoint?(cp)
    return 2u8 if wide_codepoint?(cp)
    1u8
  end

  # Returns the display width of a grapheme cluster (String).
  #
  # Uses Crystal's built-in grapheme segmentation to handle combining
  # sequences, ZWJ sequences, and emoji correctly.
  #
  # Parameters:
  # - `grapheme`: A String representing a single grapheme cluster
  #
  # Returns `0`, `1`, or `2` for display columns.
  #
  # ```
  # UnicodeWidth.grapheme_width("e\u{301}")         # => 1 (é as combining sequence)
  # UnicodeWidth.grapheme_width("\u{26A0}\u{FE0E}") # => 1 (⚠︎ text presentation)
  # UnicodeWidth.grapheme_width("\u{26A0}\u{FE0F}") # => 2 (⚠️ emoji presentation)
  # UnicodeWidth.grapheme_width("👨‍👩‍👧‍👦")          # => 2 (family emoji ZWJ sequence)
  # UnicodeWidth.grapheme_width("🇺🇸")               # => 2 (regional indicator flag)
  # ```
  def self.grapheme_width(grapheme : String) : UInt8
    return 0u8 if grapheme.empty?

    # Handle regional indicator pairs (flags)
    return 2u8 if regional_indicator_pair?(grapheme)

    # Sum codepoint widths, then normalize clusters
    width = calculate_grapheme_raw_width(grapheme)
    return 0u8 if width == 0

    # Cluster normalization rules
    return 1u8 if grapheme.includes?('\u{FE0E}')              # VS15: text presentation
    return 2u8 if grapheme.includes?('\u{FE0F}')              # VS16: emoji presentation
    return 2u8 if grapheme.includes?('\u{200D}') && width > 1 # ZWJ with emoji

    # Lone regional indicator (shouldn't happen in valid grapheme)
    return 1u8 if regional_indicator?(grapheme.char_at(0).ord)

    # Return calculated width, capped at 2
    width > 2 ? 2u8 : width.to_u8
  end

  # Returns the display width of a string (multiple grapheme clusters).
  #
  # Uses Crystal's grapheme segmentation and sums grapheme widths.
  #
  # Parameters:
  # - `text`: Any String
  #
  # Returns total column width.
  #
  # ```
  # UnicodeWidth.string_width("Hello") # => 5
  # UnicodeWidth.string_width("你好")    # => 4
  # UnicodeWidth.string_width("café")  # => 4
  # ```
  def self.string_width(text : String) : Int32
    return 0 if text.empty?

    width = 0
    text.each_grapheme do |grapheme|
      width += grapheme_width(grapheme.to_s)
    end
    width
  end

  # :nodoc:
  private def self.zero_width_codepoint?(cp : Int32) : Bool
    # Non-printable and control characters
    return true if cp < 32 || (cp >= 0x7F && cp <= 0x9F)

    # Zero-width categories
    combining_mark?(cp) ||
      variation_selector?(cp) ||
      emoji_modifier?(cp) ||
      format_control?(cp)
  end

  # :nodoc:
  private def self.format_control?(cp : Int32) : Bool
    # Zero Width Joiner, Non-Joiner, Zero Width Space, Word Joiner
    cp == 0x200D || cp == 0x200C || cp == 0x200B || cp == 0x2060
  end

  # :nodoc:
  private def self.calculate_grapheme_raw_width(grapheme : String) : UInt32
    width = 0u32

    grapheme.each_char do |char|
      width += codepoint_width(char.ord)
    end

    width
  end

  # :nodoc:
  private def self.combining_mark?(cp : Int32) : Bool
    # Combining Diacritical Marks
    (0x0300..0x036F).includes?(cp) ||
      # Combining Diacritical Marks Extended
      (0x1AB0..0x1AFF).includes?(cp) ||
      # Combining Diacritical Marks Supplement
      (0x1DC0..0x1DFF).includes?(cp) ||
      # Combining Marks for Symbols
      (0x20D0..0x20FF).includes?(cp) ||
      # Combining Half Marks
      (0xFE20..0xFE2F).includes?(cp)
  end

  # :nodoc:
  private def self.variation_selector?(cp : Int32) : Bool
    # Variation Selectors
    (0xFE00..0xFE0F).includes?(cp) ||
      # Variation Selectors Supplement
      (0xE0100..0xE01EF).includes?(cp)
  end

  # :nodoc:
  private def self.emoji_modifier?(cp : Int32) : Bool
    # Emoji skin tone modifiers (U+1F3FB..U+1F3FF)
    (0x1F3FB..0x1F3FF).includes?(cp)
  end

  # :nodoc:
  private def self.regional_indicator?(cp : Int32) : Bool
    # Regional Indicator Symbols (A-Z)
    (0x1F1E6..0x1F1FF).includes?(cp)
  end

  # :nodoc:
  private def self.regional_indicator_pair?(grapheme : String) : Bool
    # Check if string has exactly 2 regional indicators (flag emoji)
    return false if grapheme.empty?

    cps = grapheme.chars.map(&.ord)
    cps.size == 2 && regional_indicator?(cps[0]) && regional_indicator?(cps[1])
  end

  # :nodoc:
  private def self.wide_codepoint?(cp : Int32) : Bool
    wide_cjk?(cp) || wide_compat_or_fullwidth?(cp) || wide_supplementary?(cp)
  end

  # CJK Unified, Extension A, Hangul, Hiragana, Katakana, Radicals, Jamo
  private def self.wide_cjk?(cp : Int32) : Bool
    (0x1100..0x115F).includes?(cp) ||   # Hangul Jamo
      (0x2E80..0x303E).includes?(cp) || # CJK Radicals
      (0x3040..0x33BF).includes?(cp) || # Hiragana, Katakana, CJK
      (0x3400..0x4DBF).includes?(cp) || # CJK Extension A
      (0x4E00..0x9FFF).includes?(cp) || # CJK Unified Ideographs
      (0xAC00..0xD7AF).includes?(cp) || # Hangul Syllables
      (0xF900..0xFAFF).includes?(cp) || # CJK Compatibility Ideographs
      cp == 0x2329 || cp == 0x232A      # Angle brackets
  end

  # CJK Compatibility Forms, Fullwidth Forms and Signs
  private def self.wide_compat_or_fullwidth?(cp : Int32) : Bool
    (0xFE10..0xFE19).includes?(cp) ||   # Vertical Forms
      (0xFE30..0xFE6F).includes?(cp) || # CJK Compatibility Forms
      (0xFF00..0xFF60).includes?(cp) || # Fullwidth Forms
      (0xFFE0..0xFFE6).includes?(cp)    # Fullwidth Signs
  end

  # Emoji and CJK supplementary planes (Extensions B-F, Tertiary)
  private def self.wide_supplementary?(cp : Int32) : Bool
    (0x1F300..0x1FAFF).includes?(cp) ||   # Emoji
      (0x20000..0x2FFFD).includes?(cp) || # CJK Extensions B-F
      (0x30000..0x3FFFD).includes?(cp)    # CJK Tertiary Ideographic
  end
end
