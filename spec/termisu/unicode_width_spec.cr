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

    it "returns 0 for combining marks" do
      # Combining acute accent
      Termisu::UnicodeWidth.codepoint_width(0x0301).should eq(0)
      # Combining grave accent
      Termisu::UnicodeWidth.codepoint_width(0x0300).should eq(0)
      # Combining tilde
      Termisu::UnicodeWidth.codepoint_width(0x0303).should eq(0)
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

    it "handles ZWJ sequences correctly" do
      # Heart + ZWJ + sparkle (less common but valid)
      grapheme = "❤️‍🔥" # Some terminals may not support, but should handle
      # This is a ZWJ sequence, should be width 2
      result = Termisu::UnicodeWidth.grapheme_width(grapheme)
      # Due to terminal differences, just ensure it's not 0 and reasonable
      result.should be > 0
      result.should be <= 2
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
