require "../../spec_helper"
require "digest/sha256"

# A deterministic byte reader makes consumption and following-event checks
# independent of fd buffering and scheduler timing.
private class InPlaceParserReader < Termisu::Reader
  getter consumed = 0

  def initialize(@bytes : Bytes)
    super(-1)
  end

  def read_byte(timeout_ms : Int32) : UInt8?
    return if @consumed >= @bytes.size

    byte = @bytes[@consumed]
    @consumed += 1
    byte
  end

  def peek_byte(timeout_ms : Int32) : UInt8?
    @bytes[@consumed]?
  end
end

private class InPlaceParserProbe < Termisu::Input::Parser
  def append_state(io : IO) : Nil
    io << (@protocol_active ? 1 : 0) << ':' << (@dup_guard.try(&.ord) || -1)
    io << ':' << (@in_paste ? 1 : 0) << ':' << @pending.size
    @pending.each { |byte| io << ':' << byte }
    io << ':' << (@paste_deadline.nil? ? 0 : 1)
  end
end

private class ParserCorpusRandom
  def initialize(@value = 0xC0FFEE_u32)
  end

  def next(modulus : Int32) : Int32
    @value = @value &* 1_664_525_u32 &+ 1_013_904_223_u32
    (@value % modulus).to_i32
  end
end

private def parse_in_place(bytes : Bytes) : {Termisu::Event::Any?, InPlaceParserReader}
  reader = InPlaceParserReader.new(bytes)
  {Termisu::Input::Parser.new(reader).poll_event(0), reader}
end

private def append_parser_event(io : IO, event : Termisu::Event::Any?) : Nil
  case event
  when Termisu::Event::Key
    io << "K:" << event.key.value << ':' << event.modifiers.value << ':' << (event.char.try(&.ord) || -1)
  when Termisu::Event::Mouse
    io << "M:" << event.x << ':' << event.y << ':' << event.button.value
    io << ':' << event.modifiers.value << ':' << (event.motion? ? 1 : 0)
  when Termisu::Event::Preedit
    io << "P:"
    event.text.to_slice.each { |byte| io << byte.to_s(16) << ',' }
  when Nil
    io << 'N'
  else
    io << 'O'
  end
end

private def append_corpus_case(digest : Digest::SHA256, case_index : Int32, bytes : Array(UInt8)) : Nil
  slice = Slice.new(bytes.to_unsafe, bytes.size)
  reader = InPlaceParserReader.new(slice)
  parser = InPlaceParserProbe.new(reader)
  io = IO::Memory.new
  io << case_index << ':' << bytes.join(',') << ':'

  5.times do
    append_parser_event(io, parser.poll_event(0))
    io << '@' << reader.consumed << '@'
    parser.append_state(io)
    io << '|'
  end
  io << '\n'
  digest.update(io.to_slice)
end

private def parser_allocated_bytes(sequence : Bytes, count : Int32) : UInt64
  payload = Bytes.new(sequence.size * (count + 1)) { |index| sequence[index % sequence.size] }
  reader = InPlaceParserReader.new(payload)
  parser = Termisu::Input::Parser.new(reader)
  parser.poll_event(0) # Warm parser state before measuring identical events.
  GC.collect
  before = GC.stats.total_bytes
  count.times { parser.poll_event(0) }
  GC.stats.total_bytes - before
end

describe Termisu::Input::Parser do
  it "allocates nothing transient for key and mouse events and only owned Preedit text" do
    count = 500
    [
      "€".to_slice,
      "\e[1;5A".to_slice,
      "\e[97;5u".to_slice,
      "\e[27;5;112~".to_slice,
      "\e[<0;10;20M".to_slice,
      Bytes[0x1B, '['.ord, 'M'.ord, 32, 33, 33],
    ].each do |sequence|
      parser_allocated_bytes(sequence, count).should eq(0), String.new(sequence)
    end

    preedit_bytes = parser_allocated_bytes("\e[0;1;4352:4449u".to_slice, count)
    preedit_bytes.should be > 0
    preedit_bytes.should be <= 48_u64 * count
  end

  describe "in-place UTF-8 decoding" do
    it "accepts every RFC 3629 boundary" do
      {
        Bytes[0xC2, 0x80]             => 0x80,
        Bytes[0xDF, 0xBF]             => 0x7FF,
        Bytes[0xE0, 0xA0, 0x80]       => 0x800,
        Bytes[0xED, 0x9F, 0xBF]       => 0xD7FF,
        Bytes[0xEE, 0x80, 0x80]       => 0xE000,
        Bytes[0xEF, 0xBF, 0xBF]       => 0xFFFF,
        Bytes[0xF0, 0x90, 0x80, 0x80] => 0x10000,
        Bytes[0xF4, 0x8F, 0xBF, 0xBF] => 0x10FFFF,
      }.each do |bytes, codepoint|
        event, reader = parse_in_place(bytes)
        event.should be_a(Termisu::Event::Key)
        event.as(Termisu::Event::Key).char.should eq(codepoint.chr)
        reader.consumed.should eq(bytes.size)
      end
    end

    it "rejects overlong, surrogate, out-of-range, and invalid lead sequences" do
      [
        Bytes[0x80],
        Bytes[0xBF],
        Bytes[0xC0, 0x80],
        Bytes[0xC1, 0xBF],
        Bytes[0xE0, 0x9F, 0xBF],
        Bytes[0xED, 0xA0, 0x80],
        Bytes[0xF0, 0x8F, 0xBF, 0xBF],
        Bytes[0xF4, 0x90, 0x80, 0x80],
        Bytes[0xF5, 0x80, 0x80, 0x80],
        Bytes[0xF7, 0xBF, 0xBF, 0xBF],
        Bytes[0xF8],
        Bytes[0xFF],
      ].each do |bytes|
        event, reader = parse_in_place(bytes)
        event.should be_a(Termisu::Event::Key)
        event.as(Termisu::Event::Key).key.should eq(Termisu::Input::Key::Unknown)
        reader.consumed.should eq(bytes.size)
      end
    end

    it "leaves a malformed continuation for the following event" do
      reader = InPlaceParserReader.new(Bytes[0xE2, 'q'.ord])
      parser = Termisu::Input::Parser.new(reader)

      parser.poll_event(0).as(Termisu::Event::Key).key.should eq(Termisu::Input::Key::Unknown)
      reader.consumed.should eq(1)
      parser.poll_event(0).as(Termisu::Event::Key).char.should eq('q')
    end
  end

  describe "in-place CSI field scanning" do
    it "covers Kitty, modifyOtherKeys, modified tilde, generic CSI, and SGR mouse" do
      cases = {
        "\e[97:65;5:1;65:8364u" => {Termisu::Input::Key::LowerA, Termisu::Input::Modifier::Ctrl, 'A'},
        "\e[27;3;120~"          => {Termisu::Input::Key::LowerX, Termisu::Input::Modifier::Alt, 'x'},
        "\e[5;6~"               => {Termisu::Input::Key::PageUp, Termisu::Input::Modifier::Shift | Termisu::Input::Modifier::Ctrl, nil},
        "\e[1;9A"               => {Termisu::Input::Key::Up, Termisu::Input::Modifier::Meta, nil},
      }

      cases.each do |sequence, expected|
        event, _ = parse_in_place(sequence.to_slice)
        key = event.as(Termisu::Event::Key)
        key.key.should eq(expected[0])
        key.modifiers.should eq(expected[1])
        key.char.should eq(expected[2])
      end

      mouse, _ = parse_in_place("\e[<80;2147483647;1m".to_slice)
      mouse = mouse.as(Termisu::Event::Mouse)
      mouse.x.should eq(Int32::MAX)
      mouse.y.should eq(1)
      mouse.button.wheel_up?.should be_true
      mouse.ctrl?.should be_true
    end

    it "rejects overflowing fields and invalid Kitty scalar values" do
      [
        "\e[2147483648~",
        "\e[27;5;2147483648~",
        "\e[<0;2147483648;1M",
      ].each do |sequence|
        event, _ = parse_in_place(sequence.to_slice)
        event.as(Termisu::Event::Key).key.should eq(Termisu::Input::Key::Unknown)
      end

      [
        "\e[55296;1u",
        "\e[1114112;1u",
        "\e[27;1;55296~",
        "\e[27;1;1114112~",
      ].each do |sequence|
        reader = InPlaceParserReader.new((sequence + "q").to_slice)
        parser = Termisu::Input::Parser.new(reader)
        invalid = parser.poll_event(0).as(Termisu::Event::Key)
        invalid.key.should eq(Termisu::Input::Key::Unknown)
        invalid.char.should be_nil
        parser.poll_event(0).as(Termisu::Event::Key).char.should eq('q')
      end
    end

    it "preserves generic-CSI and raw-SGR numeric whitespace semantics" do
      malformed_sgr = Bytes[0x1B, '['.ord, '<'.ord, '0'.ord, ';'.ord, '1'.ord,
        0xA0, ';'.ord, '1'.ord, 'M'.ord, 'q'.ord]
      reader = InPlaceParserReader.new(malformed_sgr)
      parser = Termisu::Input::Parser.new(reader)
      parser.poll_event(0).as(Termisu::Event::Key).key.should eq(Termisu::Input::Key::Unknown)
      reader.consumed.should eq(malformed_sgr.size - 1)
      parser.poll_event(0).as(Termisu::Event::Key).char.should eq('q')

      # The former generic CSI Builder encoded byte 0xA0 as U+00A0, while the
      # former SGR String retained raw bytes. A valid UTF-8 U+00A0 remains
      # whitespace in raw SGR fields, but a lone 0xA0 must not become one.
      generic = Bytes[0x1B, '['.ord, '1'.ord, ';'.ord, '5'.ord, 0xA0, 'A'.ord]
      key, _ = parse_in_place(generic)
      key = key.as(Termisu::Event::Key)
      key.key.should eq(Termisu::Input::Key::Up)
      key.modifiers.should eq(Termisu::Input::Modifier::Ctrl)

      utf8_sgr = Bytes[0x1B, '['.ord, '<'.ord, '0'.ord, ';'.ord, '1'.ord,
        0xC2, 0xA0, ';'.ord, '1'.ord, 'M'.ord]
      parse_in_place(utf8_sgr)[0].should be_a(Termisu::Event::Mouse)
    end

    it "builds all and only valid Preedit text codepoints" do
      event, _ = parse_in_place("\e[0;1;4352::4449u".to_slice)
      preedit = event.as(Termisu::Event::Preedit)
      preedit.text.should eq("가")
      preedit.text.to_unsafe.should_not eq("가".to_unsafe)
    end

    it "preserves generic CSI versus SGR byte accounting and following events" do
      generic = Bytes[0x1B, '['.ord] + Bytes.new(16, 0x80_u8) + Bytes['A'.ord, 'q'.ord]
      reader = InPlaceParserReader.new(generic)
      parser = Termisu::Input::Parser.new(reader)
      parser.poll_event(0).as(Termisu::Event::Key).key.should eq(Termisu::Input::Key::Unknown)
      reader.consumed.should eq(18) # ESC, [, and 16 Latin-1 bytes counted as 32 UTF-8 bytes
      parser.poll_event(0).as(Termisu::Event::Key).char.should eq('A')

      sgr = Bytes[0x1B, '['.ord, '<'.ord] + Bytes.new(16, 0x80_u8) + Bytes['M'.ord, 'q'.ord]
      reader = InPlaceParserReader.new(sgr)
      parser = Termisu::Input::Parser.new(reader)
      parser.poll_event(0).as(Termisu::Event::Key).key.should eq(Termisu::Input::Key::Unknown)
      reader.consumed.should eq(20) # SGR counts raw bytes and therefore consumes its final M
      parser.poll_event(0).as(Termisu::Event::Key).char.should eq('q')
    end
  end

  it "matches the fixed-seed legacy parser corpus including state and consumption" do
    digest = Digest::SHA256.new
    random = ParserCorpusRandom.new
    alphabet = Bytes[0x00, 0x09, 0x20, '+'.ord, '-'.ord, '0'.ord, '1'.ord, '2'.ord,
      '7'.ord, '9'.ord, ':'.ord, ';'.ord, 0x80, 0xA0, 0xC3]
    finals = Bytes['A'.ord, 'B'.ord, 'Z'.ord, '~'.ord, 'u'.ord, 'x'.ord]
    templates = ["\e[97;1u", "\e[97:65;5:1;65:8364u", "\e[27;5;112~", "\e[5;5~",
                 "\e[0;1;4352:4449u", "\e[<64;500;1000M"]
    lead_groups = Bytes[0x80, 0xBF, 0xC0, 0xC1, 0xC2, 0xDF, 0xE0, 0xED,
      0xEF, 0xF0, 0xF4, 0xF5, 0xF7, 0xF8, 0xFF]

    20_777.times do |case_index|
      bytes = [] of UInt8
      case case_index % 4
      when 0
        bytes.concat Bytes[0x1B, '['.ord]
        random.next(38).times { bytes << alphabet[random.next(alphabet.size)] }
        bytes << finals[random.next(finals.size)]
      when 1
        bytes.concat Bytes[0x1B, '['.ord, '<'.ord]
        random.next(38).times { bytes << alphabet[random.next(alphabet.size)] }
        bytes << (random.next(2) == 0 ? 'M'.ord.to_u8 : 'm'.ord.to_u8)
      when 2
        bytes << lead_groups[random.next(lead_groups.size)]
        random.next(5).times { bytes << (0x70 + random.next(32)).to_u8 }
      when 3
        if case_index % 32 == 3
          # A lone raw 0xA0 in an otherwise valid SGR coordinate exposed a
          # String#to_i? compatibility gap that unshaped random fields missed.
          bytes.concat Bytes[0x1B, '['.ord, '<'.ord, '0'.ord, ';'.ord, '1'.ord,
            0xA0, ';'.ord, '1'.ord, 'M'.ord]
        else
          bytes.concat templates[random.next(templates.size)].to_slice
        end
      end
      bytes.concat Bytes['q'.ord, 0x1B, '['.ord, 'A'.ord, 'z'.ord]
      append_corpus_case(digest, case_index, bytes)
    end

    # Generated from the legacy parser at 45ed93a and checked on Crystal 1.17 and 1.21.
    digest.hexfinal.should eq("f6f47df279036d516a5c6c0f8d44c228058d181a399630e7ab5089f49b666081")
  end
end
