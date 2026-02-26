require "../spec_helper"

describe Termisu::UnicodeWidth do
  describe ".codepoint_width" do
    it "returns 1 for ASCII printable characters" do
      Termisu::UnicodeWidth.codepoint_width('A'.ord).should eq(1)
      Termisu::UnicodeWidth.codepoint_width('Z'.ord).should eq(1)
      Termisu::UnicodeWidth.codepoint_width('0'.ord).should eq(1)
      Termisu::UnicodeWidth.codepoint_width(' '.ord).should eq(1)
      Termisu::UnicodeWidth.codepoint_width('!'.ord).should eq(1)
    end

    it "returns 0 for control characters" do
      Termisu::UnicodeWidth.codepoint_width(0x00).should eq(0) # NUL
      Termisu::UnicodeWidth.codepoint_width(0x01).should eq(0) # SOH
      Termisu::UnicodeWidth.codepoint_width(0x1F).should eq(0) # US
      Termisu::UnicodeWidth.codepoint_width(0x7F).should eq(0) # DEL
      Termisu::UnicodeWidth.codepoint_width(0x80).should eq(0) # PAD
      Termisu::UnicodeWidth.codepoint_width(0x9F).should eq(0) # APC
    end

    it "returns 0 for combining marks (baseline Latin diacriticals)" do
      # Combining acute accent
      Termisu::UnicodeWidth.codepoint_width(0x0301).should eq(0)
      # Combining grave accent
      Termisu::UnicodeWidth.codepoint_width(0x0300).should eq(0)
      # Combining tilde
      Termisu::UnicodeWidth.codepoint_width(0x0303).should eq(0)
      # End of block
      Termisu::UnicodeWidth.codepoint_width(0x036F).should eq(0)
    end

    it "returns 0 for Arabic combining marks" do
      Termisu::UnicodeWidth.codepoint_width(0x064B).should eq(0) # Arabic fathatan
      Termisu::UnicodeWidth.codepoint_width(0x0650).should eq(0) # Arabic kasra
      Termisu::UnicodeWidth.codepoint_width(0x0670).should eq(0) # Arabic superscript alef
    end

    it "returns 0 for Devanagari combining marks" do
      Termisu::UnicodeWidth.codepoint_width(0x093C).should eq(0) # Devanagari sign nukta
      Termisu::UnicodeWidth.codepoint_width(0x094D).should eq(0) # Devanagari sign virama
      Termisu::UnicodeWidth.codepoint_width(0x0951).should eq(0) # Devanagari stress sign udatta
    end

    it "returns 0 for Thai combining marks" do
      Termisu::UnicodeWidth.codepoint_width(0x0E31).should eq(0) # Thai mai han akat
      Termisu::UnicodeWidth.codepoint_width(0x0E34).should eq(0) # Thai sara i
      Termisu::UnicodeWidth.codepoint_width(0x0E47).should eq(0) # Thai maitaikhu
    end

    it "returns 0 for Tibetan combining marks" do
      Termisu::UnicodeWidth.codepoint_width(0x0F71).should eq(0) # Tibetan vowel sign aa
      Termisu::UnicodeWidth.codepoint_width(0x0F35).should eq(0) # Tibetan mark ngas bzung nyi zla
    end

    it "returns 0 for CJK ideographic tone marks" do
      Termisu::UnicodeWidth.codepoint_width(0x302A).should eq(0) # CJK tone mark
      Termisu::UnicodeWidth.codepoint_width(0x302D).should eq(0) # CJK tone mark
    end

    it "returns 0 for Japanese combining dakuten/handakuten" do
      Termisu::UnicodeWidth.codepoint_width(0x3099).should eq(0) # Combining dakuten
      Termisu::UnicodeWidth.codepoint_width(0x309A).should eq(0) # Combining handakuten
    end

    it "returns 0 for SMP combining marks (Brahmi, Musical, etc.)" do
      Termisu::UnicodeWidth.codepoint_width(0x11038).should eq(0) # Brahmi vowel sign
      Termisu::UnicodeWidth.codepoint_width(0x1D167).should eq(0) # Musical combining stem
      Termisu::UnicodeWidth.codepoint_width(0x1E944).should eq(0) # Adlam alif lengthener
    end

    it "returns 0 for Cyrillic combining marks" do
      Termisu::UnicodeWidth.codepoint_width(0x0483).should eq(0) # Cyrillic titlo
      Termisu::UnicodeWidth.codepoint_width(0x0489).should eq(0) # Combining cyrillic millions sign
    end

    it "returns 0 for Bengali/Gurmukhi/Gujarati nukta" do
      Termisu::UnicodeWidth.codepoint_width(0x09BC).should eq(0) # Bengali sign nukta
      Termisu::UnicodeWidth.codepoint_width(0x0A3C).should eq(0) # Gurmukhi sign nukta
      Termisu::UnicodeWidth.codepoint_width(0x0ABC).should eq(0) # Gujarati sign nukta
    end

    it "returns 0 for variation selectors" do
      # VS15 - text presentation
      Termisu::UnicodeWidth.codepoint_width(0xFE0E).should eq(0)
      # VS16 - emoji presentation
      Termisu::UnicodeWidth.codepoint_width(0xFE0F).should eq(0)
    end

    it "returns 0 for ZWJ" do
      Termisu::UnicodeWidth.codepoint_width(0x200D).should eq(0)
    end

    it "returns 0 for bidi and format controls" do
      Termisu::UnicodeWidth.codepoint_width(0x200E).should eq(0) # LRM
      Termisu::UnicodeWidth.codepoint_width(0x200F).should eq(0) # RLM
      Termisu::UnicodeWidth.codepoint_width(0x061C).should eq(0) # ALM
      Termisu::UnicodeWidth.codepoint_width(0x202A).should eq(0) # LRE
      Termisu::UnicodeWidth.codepoint_width(0x202B).should eq(0) # RLE
      Termisu::UnicodeWidth.codepoint_width(0x202C).should eq(0) # PDF
      Termisu::UnicodeWidth.codepoint_width(0x202D).should eq(0) # LRO
      Termisu::UnicodeWidth.codepoint_width(0x202E).should eq(0) # RLO
      Termisu::UnicodeWidth.codepoint_width(0x2066).should eq(0) # LRI
      Termisu::UnicodeWidth.codepoint_width(0x2067).should eq(0) # RLI
      Termisu::UnicodeWidth.codepoint_width(0x2068).should eq(0) # FSI
      Termisu::UnicodeWidth.codepoint_width(0x2069).should eq(0) # PDI
    end

    it "returns 0 for emoji skin tone modifiers" do
      # Light skin tone
      Termisu::UnicodeWidth.codepoint_width(0x1F3FB).should eq(0)
      # Medium skin tone
      Termisu::UnicodeWidth.codepoint_width(0x1F3FC).should eq(0)
      # Dark skin tone
      Termisu::UnicodeWidth.codepoint_width(0x1F3FF).should eq(0)
    end

    it "returns 2 for CJK characters" do
      # Common CJK
      Termisu::UnicodeWidth.codepoint_width('中'.ord).should eq(2)
      Termisu::UnicodeWidth.codepoint_width('日'.ord).should eq(2)
      Termisu::UnicodeWidth.codepoint_width('本'.ord).should eq(2)
      Termisu::UnicodeWidth.codepoint_width('한'.ord).should eq(2)
    end

    it "returns 2 for Hangul Jamo" do
      Termisu::UnicodeWidth.codepoint_width(0x1100).should eq(2)
      Termisu::UnicodeWidth.codepoint_width(0x115F).should eq(2)
    end

    it "returns 2 for Hiragana and Katakana" do
      # Hiragana
      Termisu::UnicodeWidth.codepoint_width('あ'.ord).should eq(2)
      Termisu::UnicodeWidth.codepoint_width('い'.ord).should eq(2)
      # Katakana
      Termisu::UnicodeWidth.codepoint_width('ア'.ord).should eq(2)
      Termisu::UnicodeWidth.codepoint_width('イ'.ord).should eq(2)
    end

    it "returns 2 for emoji" do
      # Grinning face
      Termisu::UnicodeWidth.codepoint_width(0x1F600).should eq(2)
      # Thumbs up
      Termisu::UnicodeWidth.codepoint_width(0x1F44D).should eq(2)
      # Red heart
      Termisu::UnicodeWidth.codepoint_width(0x2764).should eq(1)  # Not in emoji block, default
      Termisu::UnicodeWidth.codepoint_width(0x1F493).should eq(2) # Heart with sparkle
    end

    it "returns 2 for fullwidth forms" do
      # Fullwidth Latin A
      Termisu::UnicodeWidth.codepoint_width(0xFF21).should eq(2)
      # Fullwidth exclamation mark
      Termisu::UnicodeWidth.codepoint_width(0xFF01).should eq(2)
    end

    it "returns 2 for CJK Extension A" do
      Termisu::UnicodeWidth.codepoint_width(0x3400).should eq(2)
      Termisu::UnicodeWidth.codepoint_width(0x4DBF).should eq(2)
    end

    it "returns 1 for default printable characters" do
      # Latin
      Termisu::UnicodeWidth.codepoint_width('a'.ord).should eq(1)
      Termisu::UnicodeWidth.codepoint_width('Z'.ord).should eq(1)
      # Numbers
      Termisu::UnicodeWidth.codepoint_width('0'.ord).should eq(1)
      # Common punctuation
      Termisu::UnicodeWidth.codepoint_width(','.ord).should eq(1)
      Termisu::UnicodeWidth.codepoint_width('.'.ord).should eq(1)
    end
  end

  describe ".grapheme_width" do
    it "returns 1 for single ASCII characters" do
      Termisu::UnicodeWidth.grapheme_width("A").should eq(1)
      Termisu::UnicodeWidth.grapheme_width(" ").should eq(1)
      Termisu::UnicodeWidth.grapheme_width("!").should eq(1)
    end

    it "returns 2 for single CJK characters" do
      Termisu::UnicodeWidth.grapheme_width("中").should eq(2)
      Termisu::UnicodeWidth.grapheme_width("日").should eq(2)
      Termisu::UnicodeWidth.grapheme_width("한").should eq(2)
    end

    it "returns 1 for combining sequences (e + combining acute = é)" do
      # e + combining acute accent
      grapheme = "e\u{0301}"
      Termisu::UnicodeWidth.grapheme_width(grapheme).should eq(1)
    end

    it "returns 1 for text presentation selector (VS15)" do
      # Warning sign with VS15 (text presentation)
      grapheme = "\u{26A0}\u{FE0E}" # ⚠︎
      Termisu::UnicodeWidth.grapheme_width(grapheme).should eq(1)
    end

    it "returns 2 for emoji presentation selector (VS16)" do
      # Warning sign with VS16 (emoji presentation)
      grapheme = "\u{26A0}\u{FE0F}" # ⚠️
      Termisu::UnicodeWidth.grapheme_width(grapheme).should eq(2)
    end

    it "returns 2 for VS16 with emoji bases outside major symbol blocks" do
      # Watch (U+231A) — Misc Technical, not in 2600..27BF
      Termisu::UnicodeWidth.grapheme_width("\u{231A}\u{FE0F}").should eq(2)
      # Squared Latin Capital Letter A (U+1F170) — below 1F300
      Termisu::UnicodeWidth.grapheme_width("\u{1F170}\u{FE0F}").should eq(2)
      # Trade Mark Sign (U+2122)
      Termisu::UnicodeWidth.grapheme_width("\u{2122}\u{FE0F}").should eq(2)
    end

    it "does not widen non-emoji base with VS16" do
      # Latin 'A' + VS16 should stay width 1
      Termisu::UnicodeWidth.grapheme_width("A\u{FE0F}").should eq(1)
      # Cyrillic Д (U+0414) + VS16
      Termisu::UnicodeWidth.grapheme_width("\u{0414}\u{FE0F}").should eq(1)
      # Latin-1 ¡ (U+00A1) + VS16
      Termisu::UnicodeWidth.grapheme_width("\u{00A1}\u{FE0F}").should eq(1)
      # Thai ก (U+0E01) + VS16
      Termisu::UnicodeWidth.grapheme_width("\u{0E01}\u{FE0F}").should eq(1)
      # Precomposed é (U+00E9) + VS16
      Termisu::UnicodeWidth.grapheme_width("\u{00E9}\u{FE0F}").should eq(1)
      # Black star (U+2605) + VS16 — NOT in Unicode Emoji property
      Termisu::UnicodeWidth.grapheme_width("\u{2605}\u{FE0F}").should eq(1)
      # Alchemical symbol 🜀 (U+1F700) + VS16 — NOT in Unicode Emoji property, EAW=Neutral
      Termisu::UnicodeWidth.grapheme_width("\u{1F700}\u{FE0F}").should eq(1)
    end

    it "returns 2 for ZWJ family emoji" do
      # Family emoji: man + ZWJ + woman + ZWJ + girl + ZWJ + boy
      grapheme = "👨‍👩‍👧‍👦"
      Termisu::UnicodeWidth.grapheme_width(grapheme).should eq(2)
    end

    it "returns 2 for regional indicator flag pairs" do
      # US flag: regional indicator U + regional indicator S
      grapheme = "🇺🇸"
      Termisu::UnicodeWidth.grapheme_width(grapheme).should eq(2)
    end

    it "returns 2 for skin tone modified emoji" do
      # Thumbs up with light skin tone
      grapheme = "👍🏻"
      Termisu::UnicodeWidth.grapheme_width(grapheme).should eq(2)
    end

    it "returns 2 for simple emoji without VS16" do
      # Basic emoji without presentation selector
      # Most terminals render emoji at width 2 by default
      Termisu::UnicodeWidth.grapheme_width("😀").should eq(2)
    end

    it "returns 0 for empty string" do
      Termisu::UnicodeWidth.grapheme_width("").should eq(0)
    end

    it "returns 2 for ZWJ heart-fire sequence" do
      # Heart on fire: ❤️ + ZWJ + 🔥
      grapheme = "❤️‍🔥"
      Termisu::UnicodeWidth.grapheme_width(grapheme).should eq(2u8)
    end

    it "returns 2 for keycap emoji sequences" do
      # Keycap clusters: base + VS16 + COMBINING ENCLOSING KEYCAP (U+20E3)
      Termisu::UnicodeWidth.grapheme_width("#\u{FE0F}\u{20E3}").should eq(2) # #️⃣
      Termisu::UnicodeWidth.grapheme_width("1\u{FE0F}\u{20E3}").should eq(2) # 1️⃣
      Termisu::UnicodeWidth.grapheme_width("0\u{FE0F}\u{20E3}").should eq(2) # 0️⃣
      Termisu::UnicodeWidth.grapheme_width("*\u{FE0F}\u{20E3}").should eq(2) # *️⃣
      Termisu::UnicodeWidth.grapheme_width("9\u{FE0F}\u{20E3}").should eq(2) # 9️⃣
    end
  end

  describe ".string_width" do
    it "returns 0 for empty string" do
      Termisu::UnicodeWidth.string_width("").should eq(0)
    end

    it "counts ASCII characters correctly" do
      Termisu::UnicodeWidth.string_width("Hello").should eq(5)
      Termisu::UnicodeWidth.string_width("World!").should eq(6)
    end

    it "counts CJK characters as width 2" do
      Termisu::UnicodeWidth.string_width("你好").should eq(4)
      Termisu::UnicodeWidth.string_width("日本語").should eq(6)
    end

    it "counts mixed ASCII and CJK correctly" do
      Termisu::UnicodeWidth.string_width("Hello世界").should eq(9) # 5 + 4
    end

    it "counts emoji as width 2" do
      Termisu::UnicodeWidth.string_width("😀😁").should eq(4)
    end

    it "counts keycap emoji as width 2" do
      # Keycap sequences: base + VS16 + COMBINING ENCLOSING KEYCAP
      Termisu::UnicodeWidth.string_width("#\u{FE0F}\u{20E3}").should eq(2) # #️⃣
      Termisu::UnicodeWidth.string_width("1\u{FE0F}\u{20E3}").should eq(2) # 1️⃣
      # VS16 attaches to immediately preceding base: "1" (w=1) + "2️⃣" (w=2) = 3
      Termisu::UnicodeWidth.string_width("12\u{FE0F}\u{20E3}").should eq(3)
    end

    it "counts combining sequences as width 1" do
      # café with combining acute on e
      text = "cafe\u{301}"
      Termisu::UnicodeWidth.string_width(text).should eq(4)
    end

    it "counts mixed content correctly" do
      # "Hi😀中" = 2 + 2 + 2 = 6
      Termisu::UnicodeWidth.string_width("Hi😀中").should eq(6)
    end

    it "uses grapheme segmentation for complex strings" do
      # Multiple combining sequences
      text = "e\u{301}a\u{301}" # é + á
      Termisu::UnicodeWidth.string_width(text).should eq(2)
    end

    it "handles spaces correctly" do
      Termisu::UnicodeWidth.string_width("Hello World").should eq(11)
    end
  end
end
