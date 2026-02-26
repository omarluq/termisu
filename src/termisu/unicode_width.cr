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
    return 2u8 if regional_indicator_pair?(grapheme)

    width = calculate_grapheme_raw_width(grapheme)
    return 0u8 if width == 0

    normalize_cluster_width(grapheme, width)
  end

  # Applies cluster normalization rules (VS15/VS16, ZWJ) to raw width.
  # :nodoc:
  private def self.normalize_cluster_width(grapheme : String, raw_width : UInt32) : UInt8
    return 1u8 if grapheme.includes?('\u{FE0E}') # VS15: text presentation
    base_cp = grapheme.char_at(0).ord
    return 2u8 if grapheme.includes?('\u{20E3}') && keycap_base?(base_cp)             # Keycap sequence (e.g. #️⃣ 1️⃣)
    return 2u8 if grapheme.includes?('\u{FE0F}') && emoji_presentation_base?(base_cp) # VS16: emoji-capable bases only
    return 2u8 if grapheme.includes?('\u{200D}') && raw_width > 1                     # ZWJ with emoji
    return 1u8 if regional_indicator?(base_cp)                                        # Lone regional indicator

    raw_width > 2 ? 2u8 : raw_width.to_u8
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
    # ZWJ, ZWNJ, ZWS, WJ, LRM, RLM (contiguous 200B..200F)
    return true if cp >= 0x200B && cp <= 0x200F
    # Word Joiner, ALM
    return true if cp == 0x2060 || cp == 0x061C
    # Embedding (202A..202E) and isolate (2066..2069) controls
    (cp >= 0x202A && cp <= 0x202E) || (cp >= 0x2066 && cp <= 0x2069)
  end

  # :nodoc:
  private def self.calculate_grapheme_raw_width(grapheme : String) : UInt32
    width = 0u32

    grapheme.each_char do |char|
      width += codepoint_width(char.ord)
    end

    width
  end

  # Unicode combining mark ranges for categories Mn (Nonspacing_Mark)
  # and Me (Enclosing_Mark). Sorted by start codepoint for binary search.
  # Derived from Unicode 15.0 character database.
  #
  # Stored as a flat array of [start, end] pairs (inclusive on both sides).
  # Index `i * 2` = range start, `i * 2 + 1` = range end.
  # Use `COMBINING_MARK_COUNT` for the number of ranges.
  COMBINING_MARK_RANGES = [
    # BMP: Latin/Cyrillic/Arabic/Indic combining marks
    0x0300, 0x036F, # Combining Diacritical Marks
    0x0483, 0x0489, # Cyrillic combining marks (Mn+Me)
    0x0610, 0x061A, # Arabic combining marks
    0x064B, 0x065F, # Arabic fathatan..wavy hamza below
    0x0670, 0x0670, # Arabic superscript alef
    0x06D6, 0x06DC, # Arabic small high ligature..small high seen
    0x06DF, 0x06E4, # Arabic small high rounded zero..small high madda
    0x06E7, 0x06E8, # Arabic small high yeh..small high noon
    0x06EA, 0x06ED, # Arabic empty centre low stop..small low meem
    0x0711, 0x0711, # Syriac letter superscript alaph
    0x0730, 0x074A, # Syriac combining marks
    0x07A6, 0x07B0, # Thaana combining marks
    0x07EB, 0x07F3, # NKo combining marks
    0x07FD, 0x07FD, # NKo dantayalan
    0x0816, 0x0819, # Samaritan marks
    0x081B, 0x0823, # Samaritan marks
    0x0825, 0x0827, # Samaritan marks
    0x0829, 0x082D, # Samaritan marks
    0x0859, 0x085B, # Mandaic combining marks
    0x0898, 0x089F, # Arabic combining marks (extended)
    0x08CA, 0x08E1, # Arabic combining marks
    0x08E3, 0x0902, # Arabic..Devanagari combining marks
    0x093A, 0x093A, # Devanagari vowel sign oe
    0x093C, 0x093C, # Devanagari sign nukta
    0x0941, 0x0948, # Devanagari vowel signs
    0x094D, 0x094D, # Devanagari sign virama
    0x0951, 0x0957, # Devanagari stress signs
    0x0962, 0x0963, # Devanagari vowel signs
    0x0981, 0x0981, # Bengali sign candrabindu
    0x09BC, 0x09BC, # Bengali sign nukta
    0x09C1, 0x09C4, # Bengali vowel signs
    0x09CD, 0x09CD, # Bengali sign virama
    0x09E2, 0x09E3, # Bengali vowel signs
    0x09FE, 0x09FE, # Bengali sandhi mark
    0x0A01, 0x0A02, # Gurmukhi signs
    0x0A3C, 0x0A3C, # Gurmukhi sign nukta
    0x0A41, 0x0A42, # Gurmukhi vowel signs
    0x0A47, 0x0A48, # Gurmukhi vowel signs
    0x0A4B, 0x0A4D, # Gurmukhi vowel signs + virama
    0x0A51, 0x0A51, # Gurmukhi sign udaat
    0x0A70, 0x0A71, # Gurmukhi tippi + addak
    0x0A75, 0x0A75, # Gurmukhi sign yakash
    0x0A81, 0x0A82, # Gujarati signs
    0x0ABC, 0x0ABC, # Gujarati sign nukta
    0x0AC1, 0x0AC5, # Gujarati vowel signs
    0x0AC7, 0x0AC8, # Gujarati vowel signs
    0x0ACD, 0x0ACD, # Gujarati sign virama
    0x0AE2, 0x0AE3, # Gujarati vowel signs
    0x0AFA, 0x0AFF, # Gujarati combining marks
    0x0B01, 0x0B01, # Oriya sign candrabindu
    0x0B3C, 0x0B3C, # Oriya sign nukta
    0x0B3F, 0x0B3F, # Oriya vowel sign i
    0x0B41, 0x0B44, # Oriya vowel signs
    0x0B4D, 0x0B4D, # Oriya sign virama
    0x0B55, 0x0B56, # Oriya signs
    0x0B62, 0x0B63, # Oriya vowel signs
    0x0B82, 0x0B82, # Tamil sign anusvara
    0x0BC0, 0x0BC0, # Tamil vowel sign ii
    0x0BCD, 0x0BCD, # Tamil sign virama
    0x0C00, 0x0C00, # Telugu sign combining candrabindu
    0x0C04, 0x0C04, # Telugu sign combining anusvara above
    0x0C3C, 0x0C3C, # Telugu sign nukta
    0x0C3E, 0x0C40, # Telugu vowel signs
    0x0C46, 0x0C48, # Telugu vowel signs
    0x0C4A, 0x0C4D, # Telugu vowel signs + virama
    0x0C55, 0x0C56, # Telugu length marks
    0x0C62, 0x0C63, # Telugu vowel signs
    0x0C81, 0x0C81, # Kannada sign candrabindu
    0x0CBC, 0x0CBC, # Kannada sign nukta
    0x0CBF, 0x0CBF, # Kannada vowel sign i
    0x0CC6, 0x0CC6, # Kannada vowel sign e
    0x0CCC, 0x0CCD, # Kannada vowel sign au + virama
    0x0CE2, 0x0CE3, # Kannada vowel signs
    0x0D00, 0x0D01, # Malayalam signs
    0x0D3B, 0x0D3C, # Malayalam signs
    0x0D41, 0x0D44, # Malayalam vowel signs
    0x0D4D, 0x0D4D, # Malayalam sign virama
    0x0D62, 0x0D63, # Malayalam vowel signs
    0x0D81, 0x0D81, # Sinhala sign candrabindu
    0x0DCA, 0x0DCA, # Sinhala sign al-lakuna
    0x0DD2, 0x0DD4, # Sinhala vowel signs
    0x0DD6, 0x0DD6, # Sinhala vowel sign diga paa-pilla
    # BMP: Thai/Lao/Tibetan/Myanmar/SE Asian combining marks
    0x0E31, 0x0E31, # Thai mai han akat
    0x0E34, 0x0E3A, # Thai vowel signs + marks
    0x0E47, 0x0E4E, # Thai maitaikhu..yamakkan
    0x0EB1, 0x0EB1, # Lao vowel sign mai kan
    0x0EB4, 0x0EBC, # Lao vowel signs + marks
    0x0EC8, 0x0ECE, # Lao tone marks
    0x0F18, 0x0F19, # Tibetan astrological signs
    0x0F35, 0x0F35, # Tibetan mark ngas bzung nyi zla
    0x0F37, 0x0F37, # Tibetan mark ngas bzung sgor rtags
    0x0F39, 0x0F39, # Tibetan mark tsa -phru
    0x0F71, 0x0F7E, # Tibetan vowel signs
    0x0F80, 0x0F84, # Tibetan vowel signs + marks
    0x0F86, 0x0F87, # Tibetan signs
    0x0F8D, 0x0F97, # Tibetan subjoined consonants
    0x0F99, 0x0FBC, # Tibetan subjoined consonants
    0x0FC6, 0x0FC6, # Tibetan symbol padma gdan
    0x102D, 0x1030, # Myanmar vowel signs
    0x1032, 0x1037, # Myanmar vowel signs + marks
    0x1039, 0x103A, # Myanmar sign virama + asat
    0x103D, 0x103E, # Myanmar consonant signs
    0x1058, 0x1059, # Myanmar vowel signs
    0x105E, 0x1060, # Myanmar consonant signs
    0x1071, 0x1074, # Myanmar vowel signs
    0x1082, 0x1082, # Myanmar consonant sign shan medial wa
    0x1085, 0x1086, # Myanmar vowel signs
    0x108D, 0x108D, # Myanmar sign shan council emphatic tone
    0x109D, 0x109D, # Myanmar vowel sign aiton ai
    # BMP: Ethiopic/Philippine/Khmer/Mongolian scripts
    0x135D, 0x135F, # Ethiopic combining marks
    0x1712, 0x1714, # Tagalog combining marks
    0x1732, 0x1733, # Hanunoo combining marks
    0x1752, 0x1753, # Buhid combining marks
    0x1772, 0x1773, # Tagbanwa combining marks
    0x17B4, 0x17B5, # Khmer vowel inherent
    0x17B7, 0x17BD, # Khmer vowel signs
    0x17C6, 0x17C6, # Khmer sign nikahit
    0x17C9, 0x17D3, # Khmer signs
    0x17DD, 0x17DD, # Khmer sign atthacan
    0x180B, 0x180D, # Mongolian free variation selectors
    0x180F, 0x180F, # Mongolian free variation selector four
    0x1885, 0x1886, # Mongolian letters
    0x18A9, 0x18A9, # Mongolian letter ali gali dagalga
    # BMP: Limbu/Buginese/Tai/Balinese/Sundanese scripts
    0x1920, 0x1922, # Limbu vowel signs
    0x1927, 0x1928, # Limbu vowel signs
    0x1932, 0x1932, # Limbu small letter anusvara
    0x1939, 0x193B, # Limbu signs
    0x1A17, 0x1A18, # Buginese vowel signs
    0x1A1B, 0x1A1B, # Buginese vowel sign ae
    0x1A56, 0x1A56, # Tai Tham consonant sign medial la
    0x1A58, 0x1A5E, # Tai Tham signs
    0x1A60, 0x1A60, # Tai Tham sign sakot
    0x1A62, 0x1A62, # Tai Tham vowel sign mai sat
    0x1A65, 0x1A6C, # Tai Tham vowel signs
    0x1A73, 0x1A7C, # Tai Tham vowel signs + marks
    0x1A7F, 0x1A7F, # Tai Tham combining cryptogrammic dot
    0x1AB0, 0x1ACE, # Combining Diacritical Marks Extended
    0x1B00, 0x1B03, # Balinese signs
    0x1B34, 0x1B34, # Balinese sign rerekan
    0x1B36, 0x1B3A, # Balinese vowel signs
    0x1B3C, 0x1B3C, # Balinese vowel sign la lenga
    0x1B42, 0x1B42, # Balinese vowel sign pepet
    0x1B6B, 0x1B73, # Balinese musical symbols
    0x1B80, 0x1B81, # Sundanese signs
    0x1BA2, 0x1BA5, # Sundanese consonant signs
    0x1BA8, 0x1BA9, # Sundanese vowel signs
    0x1BAB, 0x1BAD, # Sundanese signs
    0x1BE6, 0x1BE6, # Batak sign tompi
    0x1BE8, 0x1BE9, # Batak vowel signs
    0x1BED, 0x1BED, # Batak vowel sign karo o
    0x1BEF, 0x1BF1, # Batak vowel signs
    # BMP: Lepcha/Vedic/Symbols/CJK combining
    0x1C2C, 0x1C33, # Lepcha vowel signs
    0x1C36, 0x1C37, # Lepcha signs
    0x1CD0, 0x1CD2, # Vedic tone marks
    0x1CD4, 0x1CE0, # Vedic signs
    0x1CE2, 0x1CE8, # Vedic signs
    0x1CED, 0x1CED, # Vedic sign tiryak
    0x1CF4, 0x1CF4, # Vedic tone candra above
    0x1CF8, 0x1CF9, # Vedic tone marks
    0x1DC0, 0x1DFF, # Combining Diacritical Marks Supplement
    0x20D0, 0x20F0, # Combining Marks for Symbols
    0x2CEF, 0x2CF1, # Coptic combining marks
    0x2D7F, 0x2D7F, # Tifinagh consonant joiner
    0x2DE0, 0x2DFF, # Cyrillic Extended-A combining
    0x302A, 0x302D, # CJK ideographic tone marks
    0x3099, 0x309A, # Japanese combining dakuten/handakuten
    # BMP: Extended scripts (Cyrillic/Bamum/Syloti/Saurashtra/etc.)
    0xA66F, 0xA672, # Combining Cyrillic marks (Mn+Me)
    0xA674, 0xA67D, # Combining Cyrillic marks
    0xA69E, 0xA69F, # Cyrillic combining marks
    0xA6F0, 0xA6F1, # Bamum combining marks
    0xA802, 0xA802, # Syloti Nagri sign dvisvara
    0xA806, 0xA806, # Syloti Nagri sign hasanta
    0xA80B, 0xA80B, # Syloti Nagri sign anusvara
    0xA825, 0xA826, # Syloti Nagri vowel signs
    0xA82C, 0xA82C, # Syloti Nagri sign alternate hasanta
    0xA8C4, 0xA8C5, # Saurashtra signs
    0xA8E0, 0xA8F1, # Devanagari extended combining marks
    0xA8FF, 0xA8FF, # Devanagari vowel sign ay
    0xA926, 0xA92D, # Kayah Li combining marks
    0xA947, 0xA951, # Rejang combining marks
    0xA980, 0xA982, # Javanese signs
    0xA9B3, 0xA9B3, # Javanese sign cecak telu
    0xA9B6, 0xA9B9, # Javanese vowel signs
    0xA9BC, 0xA9BD, # Javanese vowel signs
    0xA9E5, 0xA9E5, # Myanmar sign shan saw
    0xAA29, 0xAA2E, # Cham vowel signs
    0xAA31, 0xAA32, # Cham vowel signs
    0xAA35, 0xAA36, # Cham consonant signs
    0xAA43, 0xAA43, # Cham consonant sign final ng
    0xAA4C, 0xAA4C, # Cham consonant sign final m
    0xAA7C, 0xAA7C, # Myanmar sign tai laing tone-2
    0xAAB0, 0xAAB0, # Tai Viet mai kang
    0xAAB2, 0xAAB4, # Tai Viet vowel signs
    0xAAB7, 0xAAB8, # Tai Viet vowel signs
    0xAABE, 0xAABF, # Tai Viet vowel signs
    0xAAC1, 0xAAC1, # Tai Viet tone mai tho
    0xAAEC, 0xAAED, # Meetei Mayek vowel signs
    0xAAF6, 0xAAF6, # Meetei Mayek virama
    0xABE5, 0xABE5, # Meetei Mayek vowel sign anap
    0xABE8, 0xABE8, # Meetei Mayek vowel sign unap
    0xABED, 0xABED, # Meetei Mayek apun iyek
    0xFE00, 0xFE0F, # Variation Selectors (also handled separately)
    0xFE20, 0xFE2F, # Combining Half Marks
    # SMP: Historic/scholarly scripts
    0x101FD, 0x101FD, # Phaistos Disc combining mark
    0x102E0, 0x102E0, # Coptic epact thousands mark
    0x10376, 0x1037A, # Old Permic combining marks
    0x10A01, 0x10A03, # Kharoshthi vowel signs
    0x10A05, 0x10A06, # Kharoshthi vowel signs
    0x10A0C, 0x10A0F, # Kharoshthi signs
    0x10A38, 0x10A3A, # Kharoshthi signs
    0x10A3F, 0x10A3F, # Kharoshthi virama
    0x10AE5, 0x10AE6, # Manichaean combining marks
    0x10D24, 0x10D27, # Hanifi Rohingya combining marks
    0x10EAB, 0x10EAC, # Yezidi combining marks
    0x10EFD, 0x10EFF, # Arabic extended combining marks
    0x10F46, 0x10F50, # Sogdian combining marks
    0x10F82, 0x10F85, # Old Uyghur combining marks
    # SMP: Brahmic family (Brahmi/Kaithi/Chakma/Sharada/etc.)
    0x11001, 0x11001, # Brahmi sign anusvara
    0x11038, 0x11046, # Brahmi vowel signs + virama
    0x11070, 0x11070, # Brahmi sign old Tamil short e
    0x11073, 0x11074, # Brahmi vowel signs
    0x1107F, 0x11081, # Brahmi number joiner..Kaithi signs
    0x110B3, 0x110B6, # Kaithi vowel signs
    0x110B9, 0x110BA, # Kaithi signs
    0x110C2, 0x110C2, # Kaithi vowel sign vocalic l
    0x11100, 0x11102, # Chakma signs
    0x11127, 0x1112B, # Chakma vowel signs
    0x1112D, 0x11134, # Chakma vowel signs + virama
    0x11173, 0x11173, # Mahajani sign nukta
    0x11180, 0x11181, # Sharada signs
    0x111B6, 0x111BE, # Sharada vowel signs
    0x111C9, 0x111CC, # Sharada signs
    0x111CF, 0x111CF, # Sharada sign inverted candrabindu
    0x1122F, 0x11231, # Khojki vowel signs
    0x11234, 0x11234, # Khojki sign anusvara
    0x11236, 0x11237, # Khojki signs
    0x1123E, 0x1123E, # Khojki sign sukun
    0x11241, 0x11241, # Khojki vowel sign vocalic r
    0x112DF, 0x112DF, # Khudawadi sign anusvara
    0x112E3, 0x112EA, # Khudawadi vowel signs
    0x11300, 0x11301, # Grantha signs
    0x1133B, 0x1133C, # Grantha signs
    0x11340, 0x11340, # Grantha vowel sign ii
    0x11366, 0x1136C, # Grantha combining marks
    0x11370, 0x11374, # Grantha combining marks
    0x11438, 0x1143F, # Newa vowel signs
    0x11442, 0x11444, # Newa signs
    0x11446, 0x11446, # Newa sign nukta
    0x1145E, 0x1145E, # Newa sandhi mark
    0x114B3, 0x114B8, # Tirhuta vowel signs
    0x114BA, 0x114BA, # Tirhuta vowel sign short e
    0x114BF, 0x114C0, # Tirhuta signs
    0x114C2, 0x114C3, # Tirhuta signs
    0x115B2, 0x115B5, # Siddham vowel signs
    0x115BC, 0x115BD, # Siddham signs
    0x115BF, 0x115C0, # Siddham signs
    0x115DC, 0x115DD, # Siddham vowel signs
    0x11633, 0x1163A, # Modi vowel signs
    0x1163D, 0x1163D, # Modi sign anusvara
    0x1163F, 0x11640, # Modi signs
    0x116AB, 0x116AB, # Takri sign anusvara
    0x116AD, 0x116AD, # Takri vowel sign aa
    0x116B0, 0x116B5, # Takri vowel signs
    0x116B7, 0x116B7, # Takri sign nukta
    0x1171D, 0x1171F, # Ahom consonant signs
    0x11722, 0x11725, # Ahom vowel signs
    0x11727, 0x1172B, # Ahom vowel signs + killer
    0x1182F, 0x11837, # Dogra vowel signs
    0x11839, 0x1183A, # Dogra signs
    0x1193B, 0x1193C, # Dives Akuru signs
    0x1193E, 0x1193E, # Dives Akuru virama
    0x11943, 0x11943, # Dives Akuru sign nukta
    0x119D4, 0x119D7, # Nandinagari vowel signs
    0x119DA, 0x119DB, # Nandinagari vowel signs
    0x119E0, 0x119E0, # Nandinagari sign virama
    0x11A01, 0x11A0A, # Zanabazar Square vowel signs
    0x11A33, 0x11A38, # Zanabazar Square marks
    0x11A3B, 0x11A3E, # Zanabazar Square marks
    0x11A47, 0x11A47, # Zanabazar Square subjoiner
    0x11A51, 0x11A56, # Soyombo vowel signs
    0x11A59, 0x11A5B, # Soyombo signs
    0x11A8A, 0x11A96, # Soyombo vowel/consonant signs
    0x11A98, 0x11A99, # Soyombo signs
    0x11C30, 0x11C36, # Bhaiksuki vowel signs
    0x11C38, 0x11C3D, # Bhaiksuki vowel signs + nukta
    0x11C3F, 0x11C3F, # Bhaiksuki sign virama
    0x11C92, 0x11CA7, # Marchen consonant signs
    0x11CAA, 0x11CB0, # Marchen marks
    0x11CB2, 0x11CB3, # Marchen marks
    0x11CB5, 0x11CB6, # Marchen marks
    0x11D31, 0x11D36, # Masaram Gondi vowel signs
    0x11D3A, 0x11D3A, # Masaram Gondi vowel sign e
    0x11D3C, 0x11D3D, # Masaram Gondi vowel signs
    0x11D3F, 0x11D45, # Masaram Gondi vowel signs + virama
    0x11D47, 0x11D47, # Masaram Gondi ra-kara
    0x11D90, 0x11D91, # Gunjala Gondi vowel signs
    0x11D95, 0x11D95, # Gunjala Gondi sign anusvara
    0x11D97, 0x11D97, # Gunjala Gondi virama
    0x11EF3, 0x11EF4, # Makasar vowel signs
    0x11F00, 0x11F01, # Kawi signs
    0x11F36, 0x11F3A, # Kawi vowel signs
    0x11F40, 0x11F40, # Kawi vowel sign eu
    0x11F42, 0x11F42, # Kawi conjoiner
    # SMP: Egyptian/Bassa/Hmong/Miao/Khitan
    0x13440, 0x13440, # Egyptian hieroglyph mirror horizontally
    0x13447, 0x13455, # Egyptian hieroglyph modifiers
    0x16AF0, 0x16AF4, # Bassa Vah combining marks
    0x16B30, 0x16B36, # Pahawh Hmong combining marks
    0x16F4F, 0x16F4F, # Miao sign consonant modifier bar
    0x16F8F, 0x16F92, # Miao tone marks
    0x16FE4, 0x16FE4, # Khitan small script filler
    # SMP: Musical/Signwriting/Duployan/Znamenny
    0x1BC9D, 0x1BC9E, # Duployan combining marks
    0x1CF00, 0x1CF2D, # Znamenny combining marks
    0x1CF30, 0x1CF46, # Znamenny combining marks
    0x1D167, 0x1D169, # Musical combining marks
    0x1D17B, 0x1D182, # Musical combining marks
    0x1D185, 0x1D18B, # Musical combining marks
    0x1D1AA, 0x1D1AD, # Musical combining marks
    0x1D242, 0x1D244, # Combining Greek musical tetraseme marks
    0x1DA00, 0x1DA36, # Signwriting combining marks
    0x1DA3B, 0x1DA6C, # Signwriting combining marks
    0x1DA75, 0x1DA75, # Signwriting combining mark
    0x1DA84, 0x1DA84, # Signwriting combining mark
    0x1DA9B, 0x1DA9F, # Signwriting combining marks
    0x1DAA1, 0x1DAAF, # Signwriting combining marks
    # SMP: Glagolitic/Hmong/Wancho/Mende/Adlam
    0x1E000, 0x1E006, # Glagolitic combining marks
    0x1E008, 0x1E018, # Glagolitic combining marks
    0x1E01B, 0x1E021, # Glagolitic combining marks
    0x1E023, 0x1E024, # Glagolitic combining marks
    0x1E026, 0x1E02A, # Glagolitic combining marks
    0x1E08F, 0x1E08F, # Cyrillic combining mark
    0x1E130, 0x1E136, # Nyiakeng Puachue Hmong tone marks
    0x1E2AE, 0x1E2AE, # Wancho tone mark
    0x1E2EC, 0x1E2EF, # Mende Kikakui combining marks
    0x1E4EC, 0x1E4EF, # Cypro-Minoan combining marks
    0x1E8D0, 0x1E8D6, # Mende Kikakui combining marks (numbers)
    0x1E944, 0x1E94A, # Adlam combining marks
    # SSP: Variation Selectors Supplement
    0xE0100, 0xE01EF, # Variation Selectors Supplement
  ]

  # Number of ranges in COMBINING_MARK_RANGES (array size / 2).
  COMBINING_MARK_COUNT = COMBINING_MARK_RANGES.size // 2

  # :nodoc:
  private def self.combining_mark?(cp : Int32) : Bool
    # Binary search over sorted combining mark ranges (Mn/Me categories).
    # Ranges are stored as flat pairs: [start0, end0, start1, end1, ...].
    low = 0
    high = COMBINING_MARK_COUNT - 1

    while low <= high
      mid = low + (high - low) // 2
      range_start = COMBINING_MARK_RANGES[mid * 2]
      range_end = COMBINING_MARK_RANGES[mid * 2 + 1]

      if cp < range_start
        high = mid - 1
      elsif cp > range_end
        low = mid + 1
      else
        return true
      end
    end

    false
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
    # Check if string has exactly 2 regional indicators (flag emoji).
    # Iterates codepoints directly to avoid allocating an intermediate array.
    count = 0
    grapheme.each_char do |char|
      return false unless regional_indicator?(char.ord)
      count += 1
      return false if count > 2
    end
    count == 2
  end

  # Returns true if the codepoint has the Unicode `Emoji` property and can be
  # widened by VS16 (U+FE0F). Based on Unicode 15 emoji-data.txt.
  # Uses block ranges for dense regions and binary search for singletons.
  # :nodoc:
  private def self.emoji_presentation_base?(cp : Int32) : Bool
    emoji_presentation_block?(cp) || emoji_presentation_singleton?(cp)
  end

  # Dense emoji sub-blocks in the SMP where virtually all codepoints
  # have the Unicode Emoji property. Non-emoji blocks (Alchemical Symbols,
  # Ornamental Dingbats, Supplemental Arrows, etc.) are excluded;
  # scattered emoji outside these ranges live in the singleton table.
  # :nodoc:
  private def self.emoji_presentation_block?(cp : Int32) : Bool
    (0x1F300..0x1F64F).includes?(cp) ||   # Misc Symbols & Pictographs + Emoticons
      (0x1F680..0x1F6FF).includes?(cp) || # Transport & Map Symbols
      (0x1F900..0x1F9FF).includes?(cp) || # Supplemental Symbols & Pictographs
      (0x1FA70..0x1FAFF).includes?(cp)    # Symbols & Pictographs Extended-A
  end

  # Scattered emoji-capable codepoints outside the SMP block.
  # Sorted for O(log n) binary search lookup.
  # :nodoc:
  private def self.emoji_presentation_singleton?(cp : Int32) : Bool
    EMOJI_PRESENTATION_SINGLETONS.bsearch { |entry| entry >= cp } == cp
  end

  # Keycap base characters: digits 0-9, '#', '*'.
  # These combine with U+FE0F + U+20E3 to form keycap emoji sequences.
  # :nodoc:
  private def self.keycap_base?(cp : Int32) : Bool
    (cp >= 0x30 && cp <= 0x39) || cp == 0x23 || cp == 0x2A
  end

  # Sorted codepoints with the Unicode `Emoji` property that fall outside
  # the 4 dense SMP sub-blocks. Source: Unicode 15 emoji-data.txt.
  # BMP emoji (2600..27BF) are enumerated individually since those ranges
  # contain many non-emoji symbols (e.g. ★ U+2605). SMP emoji outside the
  # dense blocks (1F300..1F64F, 1F680..1F6FF, 1F900..1F9FF, 1FA70..1FAFF)
  # are also listed here.
  private EMOJI_PRESENTATION_SINGLETONS = [
    # Basic Latin and Latin-1 Supplement
    0x00A9, 0x00AE, # ©®
    # General Punctuation and Arrows
    0x200D, 0x203C, 0x2049,                                         # ZWJ ‼⁉
    0x2122, 0x2139,                                                 # ™ℹ
    0x2194, 0x2195, 0x2196, 0x2197, 0x2198, 0x2199, 0x21A9, 0x21AA, # ↔..↪
    # Misc Technical and Enclosed Alphanumerics
    0x231A, 0x231B, 0x2328, 0x23CF,                         # ⌚⌛⌨⏏
    0x23E9, 0x23EA, 0x23EB, 0x23EC, 0x23ED, 0x23EE, 0x23EF, # ⏩..⏯
    0x23F0, 0x23F1, 0x23F2, 0x23F3, 0x23F8, 0x23F9, 0x23FA, # ⏰..⏺
    0x24C2,                                                 # Ⓜ
    # Geometric Shapes
    0x25AA, 0x25AB, 0x25B6, 0x25C0, 0x25FB, 0x25FC, 0x25FD, 0x25FE, # ▪▫▶◀◻..◾
    # Misc Symbols (2600..26FF) — ONLY Emoji property codepoints
    0x2600, 0x2601, 0x2602, 0x2603, 0x2604,         # ☀☁☂☃☄
    0x260E,                                         # ☎
    0x2611,                                         # ☑
    0x2614, 0x2615,                                 # ☔☕
    0x2618,                                         # ☘
    0x261D,                                         # ☝
    0x2620, 0x2622, 0x2623,                         # ☠☢☣
    0x2626, 0x262A,                                 # ☦☪
    0x262E, 0x262F,                                 # ☮☯
    0x2638, 0x2639, 0x263A,                         # ☸☹☺
    0x2640, 0x2642,                                 # ♀♂
    0x2648, 0x2649, 0x264A, 0x264B, 0x264C, 0x264D, # ♈..♍
    0x264E, 0x264F, 0x2650, 0x2651, 0x2652, 0x2653, # ♎..♓
    0x265F,                                         # ♟
    0x2660, 0x2663,                                 # ♠♣
    0x2665, 0x2666, 0x2668,                         # ♥♦♨
    0x267B, 0x267E, 0x267F,                         # ♻♾♿
    0x2692, 0x2693, 0x2694, 0x2695, 0x2696, 0x2697, # ⚒..⚗
    0x2699,                                         # ⚙
    0x269B, 0x269C,                                 # ⚛⚜
    0x26A0,                                         # ⚠
    0x26A1,                                         # ⚡
    0x26A7,                                         # ⚧
    0x26AA, 0x26AB,                                 # ⚪⚫
    0x26B0, 0x26B1,                                 # ⚰⚱
    0x26BD, 0x26BE,                                 # ⚽⚾
    0x26C4, 0x26C5,                                 # ⛄⚅
    0x26C8,                                         # ⚈
    0x26CE, 0x26CF,                                 # ⚎⚏
    0x26D1,                                         # ⚑
    0x26D3, 0x26D4,                                 # ⚓⚔
    0x26E9, 0x26EA,                                 # ⚩⚪
    0x26F0, 0x26F1, 0x26F2, 0x26F3, 0x26F4, 0x26F5, # ⚰..⚵
    0x26F7, 0x26F8, 0x26F9, 0x26FA,                 # ⚷..⚺
    0x26FD,                                         # ⛽
    # Dingbats (2700..27BF) — ONLY Emoji property codepoints
    0x2702,                                         # ✂
    0x2705,                                         # ✅
    0x2708, 0x2709, 0x270A, 0x270B, 0x270C, 0x270D, # ✈..✍
    0x270F,                                         # ✏
    0x2712,                                         # ✒
    0x2714,                                         # ✔
    0x2716,                                         # ✖
    0x271D,                                         # ✝
    0x2721,                                         # ✡
    0x2728,                                         # ✨
    0x2733, 0x2734,                                 # ✳✴
    0x2744,                                         # ❄
    0x2747,                                         # ❇
    0x274C, 0x274E,                                 # ❌❎
    0x2753, 0x2754, 0x2755,                         # ❕❖❗
    0x2763, 0x2764,                                 # ❣❤
    0x2795, 0x2796, 0x2797,                         # ➕➖➗
    0x27A1,                                         # ➡
    0x27B0,                                         # ➰
    0x27BF,                                         # ➿
    # Supplemental Arrows-A/B
    0x2934, 0x2935, # ⤴⤵
    # CJK Letters and Months
    0x3030, 0x303D, # 〰〽
    0x3297, 0x3299, # ㊗㊙
    # SMP emoji with Unicode Emoji property OUTSIDE the 4 dense sub-blocks
    # (1F300..1F64F, 1F680..1F6FF, 1F900..1F9FF, 1FA70..1FAFF).
    # Source: Unicode 15 emoji-data.txt.
    0x1F004, 0x1F0CF,                            # 🀄🃏 Mahjong, Playing Cards
    0x1F170, 0x1F171, 0x1F17E, 0x1F17F, 0x1F18E, # 🅰🅱🅾🅿🆎 Squared Latin
    0x1F191, 0x1F192, 0x1F193, 0x1F194, 0x1F195, # 🆑..🆕
    0x1F196, 0x1F197, 0x1F198, 0x1F199, 0x1F19A, # 🆖..🆚
    0x1F201, 0x1F202, 0x1F21A, 0x1F22F,          # 🈁🈂🈚🈯
    0x1F232, 0x1F233, 0x1F234, 0x1F235, 0x1F236, # 🈲..🈶
    0x1F237, 0x1F238, 0x1F239, 0x1F23A,          # 🈷..🈺
    0x1F250, 0x1F251,                            # 🉐🉑
    # Geometric Shapes Extended — only emoji codepoints
    0x1F7E0, 0x1F7E1, 0x1F7E2, 0x1F7E3, 0x1F7E4, 0x1F7E5, # 🟠..🟥
    0x1F7E6, 0x1F7E7, 0x1F7E8, 0x1F7E9, 0x1F7EA, 0x1F7EB, # 🟦..🟫
    0x1F7F0,                                              # 🟰 Heavy equals sign
  ]

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

  # Emoji and CJK supplementary planes (Extensions B-F, Tertiary).
  # Excludes Alchemical Symbols (1F700-1F77F), Geometric Shapes Extended
  # (1F780-1F7DF), Supplemental Arrows-C (1F800-1F8FF), and Chess Symbols
  # (1FA00-1FA6F) which have EAW = Neutral and are NOT emoji.
  # Uses selected emoji ranges from Unicode 15 emoji-data.txt, including
  # some broad contiguous blocks where most codepoints are emoji.
  private def self.wide_supplementary?(cp : Int32) : Bool
    (0x1F300..0x1F6FF).includes?(cp) ||   # Misc Symbols & Pictographs through Transport
      (0x1F7E0..0x1F7EB).includes?(cp) || # Geometric Shapes Ext — colored circles/squares (emoji)
      cp == 0x1F7F0 ||                    # Heavy equals sign (emoji)
      (0x1F90C..0x1F9FF).includes?(cp) || # Supplemental Symbols & Pictographs (emoji portion)
      (0x1FA70..0x1FAFF).includes?(cp) || # Symbols & Pictographs Extended-A
      (0x20000..0x2FFFD).includes?(cp) || # CJK Extensions B-F
      (0x30000..0x3FFFD).includes?(cp)    # CJK Tertiary Ideographic
  end
end
