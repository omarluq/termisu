require "../../spec_helper"

# Helper to write bytes to pipe and parse event.
# Specific to parser tests - uses create_pipe from PipeHelpers.
private def parse_sequence(bytes : Bytes) : Termisu::Event::Any?
  parse_sequence_with_buffer(bytes, 128, 100)
end

# A tiny Reader buffer forces every continuation byte through the fd-read
# boundary. This catches parser paths that accidentally assume the first fill
# contains a whole terminal sequence.
private def parse_sequence_with_buffer(bytes : Bytes, buffer_size : Int32,
                                       timeout_ms : Int32) : Termisu::Event::Any?
  read_fd, write_fd = create_pipe
  begin
    LibC.write(write_fd, bytes, bytes.size)
    reader = Termisu::Reader.new(read_fd, buffer_size)
    parser = Termisu::Input::Parser.new(reader)
    parser.poll_event(timeout_ms)
  ensure
    reader.try(&.close)
    LibC.close(read_fd)
    LibC.close(write_fd)
  end
end

# Writes *head* now and *tail* after *gap_ms*, the second write coming from a
# CHILD PROCESS on purpose: the reader waits in select(2), which does not yield to
# the Crystal scheduler, so a `spawn`ed fiber would never get to run the delayed
# write and the split could not be reproduced in-process.
private def parse_events_delayed_tail(head : Bytes, tail : String, gap_ms : Int32,
                                      count : Int32) : Array(Termisu::Event::Any?)
  read_fd, write_fd = create_pipe
  events = [] of Termisu::Event::Any?
  sink = IO::FileDescriptor.new(write_fd)
  begin
    sink.write(head)
    sink.flush
    writer = Process.new("sh", ["-c", "sleep #{gap_ms / 1000.0}; printf '%s' '#{tail}'"],
      output: sink)
    reader = Termisu::Reader.new(read_fd)
    parser = Termisu::Input::Parser.new(reader)
    # Poll until *count* events arrive rather than polling exactly *count* times.
    # A poll budget that expires while the end-marker probe is still open yields
    # nil and the probe resumes on the next call, which is what a real event loop
    # does; polling a fixed number of times would record that nil as an event.
    # Bounded so a genuine failure to deliver still ends the spec.
    deadline = monotonic_now + (gap_ms + 2000).milliseconds
    while events.size < count && monotonic_now < deadline
      if event = parser.poll_event(100)
        events << event
      end
    end
  ensure
    writer.try(&.wait)
    reader.try(&.close)
    LibC.close(read_fd)
    sink.close
  end
  events
end

# Keys of the events in *events*, for asserting the shape of a whole paste.
# Pairs with `parse_events`, defined at the foot of this file.
private def keys_of(events : Array(Termisu::Event::Any?)) : Array(Termisu::Input::Key?)
  events.map { |event| event.is_a?(Termisu::Event::Key) ? event.key : nil }
end

# Exposes the private rounding so the boundary cases can be pinned directly: the
# clock read in `ms_until` cannot be made to yield an exact fractional millisecond.
private class ParserRoundingProbe < Termisu::Input::Parser
  def ceil(remaining : Float64) : Int32
    ceil_ms(remaining)
  end
end

# Deterministic reader used to prove that continuation waits share one deadline.
# Byte N arrives N * gap_ms after parsing starts; waits advance a virtual clock
# instead of sleeping, so the regression remains reliable on loaded builders.
private class ParserDripReader < Termisu::Reader
  getter now : MonotonicTime
  getter consumed = 0

  def initialize(@bytes : Bytes, @gap_ms : Int32)
    super(-1)
    @now = monotonic_now
    @started_at = @now
  end

  def elapsed : Time::Span
    @now - @started_at
  end

  def read_byte(timeout_ms : Int32) : UInt8?
    wait_for_next_byte(timeout_ms, consume: true)
  end

  def peek_byte(timeout_ms : Int32) : UInt8?
    wait_for_next_byte(timeout_ms, consume: false)
  end

  private def wait_for_next_byte(timeout_ms : Int32, consume : Bool) : UInt8?
    return if @consumed >= @bytes.size

    arrival = @started_at + (@consumed * @gap_ms).milliseconds
    remaining = (arrival - @now).total_milliseconds
    if remaining > timeout_ms
      @now += timeout_ms.milliseconds
      return
    end

    @now = arrival if arrival > @now
    byte = @bytes[@consumed]
    @consumed += 1 if consume
    byte
  end
end

private class ParserDripProbe < Termisu::Input::Parser
  def initialize(reader : ParserDripReader)
    @clock = reader
    super(reader)
  end

  private def monotonic_now : MonotonicTime
    @clock.now
  end
end

describe Termisu::Input::Parser do
  # A wait is rounded up so a live deadline never truncates to a 0ms spin, but a
  # whole number is already the answer — inflating it would overshoot the budget
  # the caller asked for on every ordinary poll.
  describe "wait rounding" do
    it "rounds a fraction up and leaves an exact millisecond alone" do
      probe = ParserRoundingProbe.new(Termisu::Reader.new(0))

      probe.ceil(0.25).should eq(1)
      probe.ceil(1.0).should eq(1)
      probe.ceil(1.25).should eq(2)
      probe.ceil(16.0).should eq(16)
      probe.ceil(0.0).should eq(0)
      probe.ceil(-1.0).should eq(0)
    end
  end

  describe "constants" do
    it "has reasonable escape timeout" do
      Termisu::Input::Parser::ESCAPE_TIMEOUT_MS.should eq(50)
    end

    it "has reasonable max sequence length" do
      Termisu::Input::Parser::MAX_SEQUENCE_LENGTH.should eq(32)
    end
  end

  describe "#poll_event" do
    context "printable characters" do
      it "parses lowercase letters" do
        event = parse_sequence(Bytes['a'.ord])
        event.should be_a(Termisu::Event::Key)
        if event.is_a?(Termisu::Event::Key)
          event.key.should eq(Termisu::Input::Key::LowerA)
          event.modifiers.none?.should be_true
        end
      end

      it "parses uppercase letters" do
        event = parse_sequence(Bytes['A'.ord])
        event.should be_a(Termisu::Event::Key)
        if event.is_a?(Termisu::Event::Key)
          event.key.should eq(Termisu::Input::Key::UpperA)
        end
      end

      it "parses digits" do
        event = parse_sequence(Bytes['5'.ord])
        event.should be_a(Termisu::Event::Key)
        if event.is_a?(Termisu::Event::Key)
          event.key.should eq(Termisu::Input::Key::Num5)
        end
      end

      it "parses space" do
        event = parse_sequence(Bytes[' '.ord])
        event.should be_a(Termisu::Event::Key)
        if event.is_a?(Termisu::Event::Key)
          event.key.should eq(Termisu::Input::Key::Space)
        end
      end

      it "parses punctuation" do
        event = parse_sequence(Bytes['.'.ord])
        event.should be_a(Termisu::Event::Key)
        if event.is_a?(Termisu::Event::Key)
          event.key.should eq(Termisu::Input::Key::Period)
        end
      end
    end

    context "control characters" do
      it "parses Ctrl+A (0x01)" do
        event = parse_sequence(Bytes[0x01])
        event.should be_a(Termisu::Event::Key)
        if event.is_a?(Termisu::Event::Key)
          event.key.should eq(Termisu::Input::Key::LowerA)
          event.ctrl?.should be_true
        end
      end

      it "parses Ctrl+C (0x03)" do
        event = parse_sequence(Bytes[0x03])
        event.should be_a(Termisu::Event::Key)
        if event.is_a?(Termisu::Event::Key)
          event.ctrl_c?.should be_true
        end
      end

      it "parses Ctrl+D (0x04)" do
        event = parse_sequence(Bytes[0x04])
        event.should be_a(Termisu::Event::Key)
        if event.is_a?(Termisu::Event::Key)
          event.ctrl_d?.should be_true
        end
      end

      it "parses Ctrl+Z (0x1A)" do
        event = parse_sequence(Bytes[0x1A])
        event.should be_a(Termisu::Event::Key)
        if event.is_a?(Termisu::Event::Key)
          event.ctrl_z?.should be_true
        end
      end

      it "parses Ctrl+Space (0x00)" do
        event = parse_sequence(Bytes[0x00])
        event.should be_a(Termisu::Event::Key)
        if event.is_a?(Termisu::Event::Key)
          event.key.should eq(Termisu::Input::Key::Space)
          event.ctrl?.should be_true
        end
      end

      it "parses Backspace (0x7F)" do
        event = parse_sequence(Bytes[0x7F])
        event.should be_a(Termisu::Event::Key)
        if event.is_a?(Termisu::Event::Key)
          event.key.should eq(Termisu::Input::Key::Backspace)
        end
      end

      it "parses Backspace (0x08) without Ctrl modifier" do
        # 0x08 is Ctrl+H in terminal encoding, but we treat it as Backspace
        event = parse_sequence(Bytes[0x08])
        event.should be_a(Termisu::Event::Key)
        if event.is_a?(Termisu::Event::Key)
          event.key.should eq(Termisu::Input::Key::Backspace)
          event.ctrl?.should be_false
        end
      end

      it "parses Tab (0x09) without Ctrl modifier" do
        # 0x09 is Ctrl+I in terminal encoding, but we treat it as Tab
        event = parse_sequence(Bytes[0x09])
        event.should be_a(Termisu::Event::Key)
        if event.is_a?(Termisu::Event::Key)
          event.key.should eq(Termisu::Input::Key::Tab)
          event.ctrl?.should be_false
        end
      end

      it "parses Enter via CR (0x0D) without Ctrl modifier" do
        # 0x0D is Ctrl+M in terminal encoding, but we treat it as Enter
        event = parse_sequence(Bytes[0x0D])
        event.should be_a(Termisu::Event::Key)
        if event.is_a?(Termisu::Event::Key)
          event.key.should eq(Termisu::Input::Key::Enter)
          event.ctrl?.should be_false
        end
      end

      it "parses Enter via LF (0x0A) without Ctrl modifier" do
        # 0x0A is Ctrl+J in terminal encoding, but we treat it as Enter
        event = parse_sequence(Bytes[0x0A])
        event.should be_a(Termisu::Event::Key)
        if event.is_a?(Termisu::Event::Key)
          event.key.should eq(Termisu::Input::Key::Enter)
          event.ctrl?.should be_false
        end
      end

      # Both bytes are Key::Enter, so `char` is the ONLY way an application can tell a
      # pasted CRLF (0x0D 0x0A — one line break) from two separate newlines. Without it
      # every pasted line gains a blank line after it.
      it "reports which byte produced Enter" do
        cr = parse_sequence(Bytes[0x0D])
        cr.should be_a(Termisu::Event::Key)
        cr.as(Termisu::Event::Key).char.should eq('\r')

        lf = parse_sequence(Bytes[0x0A])
        lf.should be_a(Termisu::Event::Key)
        lf.as(Termisu::Event::Key).char.should eq('\n')
      end
    end

    context "CSI sequences (arrow keys)" do
      it "parses Up arrow (\\e[A)" do
        event = parse_sequence(Bytes[0x1B, '['.ord, 'A'.ord])
        event.should be_a(Termisu::Event::Key)
        if event.is_a?(Termisu::Event::Key)
          event.key.should eq(Termisu::Input::Key::Up)
        end
      end

      it "parses Down arrow (\\e[B)" do
        event = parse_sequence(Bytes[0x1B, '['.ord, 'B'.ord])
        event.should be_a(Termisu::Event::Key)
        if event.is_a?(Termisu::Event::Key)
          event.key.should eq(Termisu::Input::Key::Down)
        end
      end

      it "parses Right arrow (\\e[C)" do
        event = parse_sequence(Bytes[0x1B, '['.ord, 'C'.ord])
        event.should be_a(Termisu::Event::Key)
        if event.is_a?(Termisu::Event::Key)
          event.key.should eq(Termisu::Input::Key::Right)
        end
      end

      it "parses Left arrow (\\e[D)" do
        event = parse_sequence(Bytes[0x1B, '['.ord, 'D'.ord])
        event.should be_a(Termisu::Event::Key)
        if event.is_a?(Termisu::Event::Key)
          event.key.should eq(Termisu::Input::Key::Left)
        end
      end

      it "parses Home (\\e[H)" do
        event = parse_sequence(Bytes[0x1B, '['.ord, 'H'.ord])
        event.should be_a(Termisu::Event::Key)
        if event.is_a?(Termisu::Event::Key)
          event.key.should eq(Termisu::Input::Key::Home)
        end
      end

      it "parses End (\\e[F)" do
        event = parse_sequence(Bytes[0x1B, '['.ord, 'F'.ord])
        event.should be_a(Termisu::Event::Key)
        if event.is_a?(Termisu::Event::Key)
          event.key.should eq(Termisu::Input::Key::End)
        end
      end

      it "parses BackTab (\\e[Z)" do
        event = parse_sequence(Bytes[0x1B, '['.ord, 'Z'.ord])
        event.should be_a(Termisu::Event::Key)
        if event.is_a?(Termisu::Event::Key)
          event.key.should eq(Termisu::Input::Key::BackTab)
        end
      end
    end

    context "CSI sequences with modifiers" do
      it "parses Shift+Up (\\e[1;2A)" do
        event = parse_sequence(Bytes[0x1B, '['.ord, '1'.ord, ';'.ord, '2'.ord, 'A'.ord])
        event.should be_a(Termisu::Event::Key)
        if event.is_a?(Termisu::Event::Key)
          event.key.should eq(Termisu::Input::Key::Up)
          event.shift?.should be_true
        end
      end

      it "parses Alt+Up (\\e[1;3A)" do
        event = parse_sequence(Bytes[0x1B, '['.ord, '1'.ord, ';'.ord, '3'.ord, 'A'.ord])
        event.should be_a(Termisu::Event::Key)
        if event.is_a?(Termisu::Event::Key)
          event.key.should eq(Termisu::Input::Key::Up)
          event.alt?.should be_true
        end
      end

      it "parses Ctrl+Up (\\e[1;5A)" do
        event = parse_sequence(Bytes[0x1B, '['.ord, '1'.ord, ';'.ord, '5'.ord, 'A'.ord])
        event.should be_a(Termisu::Event::Key)
        if event.is_a?(Termisu::Event::Key)
          event.key.should eq(Termisu::Input::Key::Up)
          event.ctrl?.should be_true
        end
      end

      it "parses Ctrl+Shift+Up (\\e[1;6A)" do
        event = parse_sequence(Bytes[0x1B, '['.ord, '1'.ord, ';'.ord, '6'.ord, 'A'.ord])
        event.should be_a(Termisu::Event::Key)
        if event.is_a?(Termisu::Event::Key)
          event.key.should eq(Termisu::Input::Key::Up)
          event.ctrl?.should be_true
          event.shift?.should be_true
        end
      end
    end

    context "tilde sequences (navigation/function keys)" do
      it "parses Insert (\\e[2~)" do
        event = parse_sequence(Bytes[0x1B, '['.ord, '2'.ord, '~'.ord])
        event.should be_a(Termisu::Event::Key)
        if event.is_a?(Termisu::Event::Key)
          event.key.should eq(Termisu::Input::Key::Insert)
        end
      end

      it "parses Delete (\\e[3~)" do
        event = parse_sequence(Bytes[0x1B, '['.ord, '3'.ord, '~'.ord])
        event.should be_a(Termisu::Event::Key)
        if event.is_a?(Termisu::Event::Key)
          event.key.should eq(Termisu::Input::Key::Delete)
        end
      end

      it "parses PageUp (\\e[5~)" do
        event = parse_sequence(Bytes[0x1B, '['.ord, '5'.ord, '~'.ord])
        event.should be_a(Termisu::Event::Key)
        if event.is_a?(Termisu::Event::Key)
          event.key.should eq(Termisu::Input::Key::PageUp)
        end
      end

      it "parses PageDown (\\e[6~)" do
        event = parse_sequence(Bytes[0x1B, '['.ord, '6'.ord, '~'.ord])
        event.should be_a(Termisu::Event::Key)
        if event.is_a?(Termisu::Event::Key)
          event.key.should eq(Termisu::Input::Key::PageDown)
        end
      end

      it "parses F5 (\\e[15~)" do
        event = parse_sequence(Bytes[0x1B, '['.ord, '1'.ord, '5'.ord, '~'.ord])
        event.should be_a(Termisu::Event::Key)
        if event.is_a?(Termisu::Event::Key)
          event.key.should eq(Termisu::Input::Key::F5)
        end
      end

      it "parses F6 (\\e[17~)" do
        event = parse_sequence(Bytes[0x1B, '['.ord, '1'.ord, '7'.ord, '~'.ord])
        event.should be_a(Termisu::Event::Key)
        if event.is_a?(Termisu::Event::Key)
          event.key.should eq(Termisu::Input::Key::F6)
        end
      end

      it "parses F12 (\\e[24~)" do
        event = parse_sequence(Bytes[0x1B, '['.ord, '2'.ord, '4'.ord, '~'.ord])
        event.should be_a(Termisu::Event::Key)
        if event.is_a?(Termisu::Event::Key)
          event.key.should eq(Termisu::Input::Key::F12)
        end
      end

      it "parses tilde key with modifier (\\e[5;5~)" do
        event = parse_sequence(Bytes[0x1B, '['.ord, '5'.ord, ';'.ord, '5'.ord, '~'.ord])
        event.should be_a(Termisu::Event::Key)
        if event.is_a?(Termisu::Event::Key)
          event.key.should eq(Termisu::Input::Key::PageUp)
          event.ctrl?.should be_true
        end
      end
    end

    context "bracketed paste (DEC mode 2004)" do
      # Bytes for \e[200~ and \e[201~, the markers a terminal wraps a paste in.
      paste_start = Bytes[0x1B, '['.ord, '2'.ord, '0'.ord, '0'.ord, '~'.ord]
      paste_end = Bytes[0x1B, '['.ord, '2'.ord, '0'.ord, '1'.ord, '~'.ord]

      it "parses the paste start marker (\\e[200~)" do
        event = parse_sequence(paste_start)
        event.should be_a(Termisu::Event::Key)
        if event.is_a?(Termisu::Event::Key)
          event.key.should eq(Termisu::Input::Key::PasteStart)
          event.modifiers.should eq(Termisu::Input::Modifier::None)
          # A marker inserts nothing: a caller appending event.char to a buffer
          # must not gain a stray character from the bracketing itself.
          event.char.should be_nil
        end
      end

      it "parses the paste end marker (\\e[201~)" do
        event = parse_sequence(paste_end)
        event.should be_a(Termisu::Event::Key)
        if event.is_a?(Termisu::Event::Key)
          event.key.should eq(Termisu::Input::Key::PasteEnd)
          event.modifiers.should eq(Termisu::Input::Modifier::None)
          event.char.should be_nil
        end
      end

      # The two markers used to both fall through to Key::Unknown, so a caller
      # could see that *something* happened but not whether a paste had begun
      # or ended.
      it "tells start from end" do
        parse_sequence(paste_start).should_not eq(parse_sequence(paste_end))
      end

      # The whole point of bracketing: the terminal stops translating line
      # endings inside a paste, and termisu must not re-introduce a
      # translation of its own. A pasted CRLF stays two events carrying the
      # exact bytes that arrived.
      it "reports a CRLF inside a paste as the bytes that arrived" do
        bytes = Bytes[
          0x1B, '['.ord, '2'.ord, '0'.ord, '0'.ord, '~'.ord,
          'A'.ord, 0x0D, 0x0A, 'B'.ord,
          0x1B, '['.ord, '2'.ord, '0'.ord, '1'.ord, '~'.ord,
        ]
        events = parse_events(bytes, 6)

        keys_of(events).should eq([
          Termisu::Input::Key::PasteStart,
          Termisu::Input::Key::UpperA,
          Termisu::Input::Key::Enter,
          Termisu::Input::Key::Enter,
          Termisu::Input::Key::UpperB,
          Termisu::Input::Key::PasteEnd,
        ])
        events[2].as(Termisu::Event::Key).char.should eq('\r')
        events[3].as(Termisu::Event::Key).char.should eq('\n')
      end

      # A terminal can be interrupted, or the mode can be turned off mid-paste.
      # The parser holds no paste state, so a start with no matching end must
      # leave the following input parsing normally.
      it "keeps parsing after an unterminated paste start" do
        bytes = Bytes[0x1B, '['.ord, '2'.ord, '0'.ord, '0'.ord, '~'.ord, 'x'.ord]
        events = parse_events(bytes, 2)

        keys_of(events).should eq([
          Termisu::Input::Key::PasteStart,
          Termisu::Input::Key::LowerX,
        ])
      end

      # A stray end marker is equally survivable — nothing anywhere is armed by
      # a start.
      it "keeps parsing after an unmatched paste end" do
        bytes = Bytes[0x1B, '['.ord, '2'.ord, '0'.ord, '1'.ord, '~'.ord, 'x'.ord]
        events = parse_events(bytes, 2)

        keys_of(events).should eq([
          Termisu::Input::Key::PasteEnd,
          Termisu::Input::Key::LowerX,
        ])
      end

      # The end marker is the one escape byte guaranteed to sit at the tail of an
      # arbitrarily large transfer, so it is the one most exposed to jitter: ssh/mosh
      # or a loaded machine can land its ESC and its remaining five bytes in different
      # reads. Parsed as a sequence, a gap past ESCAPE_TIMEOUT_MS resolves the ESC as a
      # bare Escape and spills `[201~` into the document as text — and the lost PasteEnd
      # wedges a boolean consumer permanently "pasting". 200ms is 4x that timeout.
      it "finds the end marker even when its ESC arrives long before the rest" do
        head = Bytes[0x1B, '['.ord, '2'.ord, '0'.ord, '0'.ord, '~'.ord,
          'a'.ord, 'b'.ord, 0x1B]
        events = parse_events_delayed_tail(head, "[201~", 200, 4)

        keys_of(events).should eq([
          Termisu::Input::Key::PasteStart,
          Termisu::Input::Key::LowerA,
          Termisu::Input::Key::LowerB,
          Termisu::Input::Key::PasteEnd,
        ])
      end

      # The marker window must not be charged to the caller. Waiting it out inside one
      # poll would block a 16ms render loop for a full second on a truncated paste —
      # ~60 dropped frames from a silent contract violation. The probe is advanced by
      # whatever time each call has and resumes on the next, so a short budget costs
      # latency, never the marker (the spec above proves the marker still arrives).
      it "honors the caller's poll budget while an end-marker probe is open" do
        read_fd, write_fd = create_pipe
        begin
          # Opens a paste, then a dangling ESC with nothing behind it: the probe stays
          # open for the full PASTE_END_TIMEOUT_MS window.
          bytes = Bytes[0x1B, '['.ord, '2'.ord, '0'.ord, '0'.ord, '~'.ord, 'a'.ord, 0x1B]
          sink = IO::FileDescriptor.new(write_fd)
          sink.write(bytes)
          sink.flush

          reader = Termisu::Reader.new(read_fd)
          parser = Termisu::Input::Parser.new(reader)
          parser.poll_event(100) # PasteStart
          parser.poll_event(100) # 'a'

          elapsed = Time.measure { parser.poll_event(16) }
          elapsed.should be < 200.milliseconds
        ensure
          reader.try(&.close)
          LibC.close(read_fd)
          sink.try(&.close)
        end
      end

      # Second route to the same wedge, with no timing involved: a complete paste whose
      # CONTENT ends in a truncated escape. Parsed as a sequence, the content ESC's
      # Alt-key branch swallows the marker's ESC, or the CSI parameter buffer absorbs it
      # and the marker's `[` terminates it as a final byte. Matching the marker literally
      # keeps the content ESC as content and still closes the paste.
      it "closes the paste when the content itself ends in a bare ESC" do
        bytes = Bytes[0x1B, '['.ord, '2'.ord, '0'.ord, '0'.ord, '~'.ord,
          'a'.ord, 0x1B,
          0x1B, '['.ord, '2'.ord, '0'.ord, '1'.ord, '~'.ord]
        events = parse_events(bytes, 4)

        keys_of(events).should eq([
          Termisu::Input::Key::PasteStart,
          Termisu::Input::Key::LowerA,
          Termisu::Input::Key::Escape,
          Termisu::Input::Key::PasteEnd,
        ])
      end

      # Inside a paste an escape is content, not a keystroke to interpret: the bytes come
      # back exactly as they arrived. This is what makes the boundary uncorruptible — a
      # CSI in the pasted text can no longer consume the marker that follows it.
      it "delivers an escape sequence inside a paste as its literal bytes" do
        bytes = Bytes[0x1B, '['.ord, '2'.ord, '0'.ord, '0'.ord, '~'.ord,
          0x1B, '['.ord, 'A'.ord,
          0x1B, '['.ord, '2'.ord, '0'.ord, '1'.ord, '~'.ord]
        events = parse_events(bytes, 5)

        keys_of(events).should eq([
          Termisu::Input::Key::PasteStart,
          Termisu::Input::Key::Escape,
          Termisu::Input::Key::LeftBracket,
          Termisu::Input::Key::UpperA,
          Termisu::Input::Key::PasteEnd,
        ])
      end
    end

    context "SS3 sequences (F1-F4)" do
      it "parses F1 (\\eOP)" do
        event = parse_sequence(Bytes[0x1B, 'O'.ord, 'P'.ord])
        event.should be_a(Termisu::Event::Key)
        if event.is_a?(Termisu::Event::Key)
          event.key.should eq(Termisu::Input::Key::F1)
        end
      end

      it "parses F2 (\\eOQ)" do
        event = parse_sequence(Bytes[0x1B, 'O'.ord, 'Q'.ord])
        event.should be_a(Termisu::Event::Key)
        if event.is_a?(Termisu::Event::Key)
          event.key.should eq(Termisu::Input::Key::F2)
        end
      end

      it "parses F3 (\\eOR)" do
        event = parse_sequence(Bytes[0x1B, 'O'.ord, 'R'.ord])
        event.should be_a(Termisu::Event::Key)
        if event.is_a?(Termisu::Event::Key)
          event.key.should eq(Termisu::Input::Key::F3)
        end
      end

      it "parses F4 (\\eOS)" do
        event = parse_sequence(Bytes[0x1B, 'O'.ord, 'S'.ord])
        event.should be_a(Termisu::Event::Key)
        if event.is_a?(Termisu::Event::Key)
          event.key.should eq(Termisu::Input::Key::F4)
        end
      end

      it "parses Home via SS3 (\\eOH)" do
        event = parse_sequence(Bytes[0x1B, 'O'.ord, 'H'.ord])
        event.should be_a(Termisu::Event::Key)
        if event.is_a?(Termisu::Event::Key)
          event.key.should eq(Termisu::Input::Key::Home)
        end
      end

      it "parses End via SS3 (\\eOF)" do
        event = parse_sequence(Bytes[0x1B, 'O'.ord, 'F'.ord])
        event.should be_a(Termisu::Event::Key)
        if event.is_a?(Termisu::Event::Key)
          event.key.should eq(Termisu::Input::Key::End)
        end
      end
    end

    context "Linux console function keys (\\e[[A-\\e[[E)" do
      it "parses F1 (\\e[[A)" do
        event = parse_sequence(Bytes[0x1B, '['.ord, '['.ord, 'A'.ord])
        event.should be_a(Termisu::Event::Key)
        if event.is_a?(Termisu::Event::Key)
          event.key.should eq(Termisu::Input::Key::F1)
        end
      end

      it "parses F5 (\\e[[E)" do
        event = parse_sequence(Bytes[0x1B, '['.ord, '['.ord, 'E'.ord])
        event.should be_a(Termisu::Event::Key)
        if event.is_a?(Termisu::Event::Key)
          event.key.should eq(Termisu::Input::Key::F5)
        end
      end
    end

    context "Alt+key sequences" do
      it "parses Alt+a (\\ea)" do
        event = parse_sequence(Bytes[0x1B, 'a'.ord])
        event.should be_a(Termisu::Event::Key)
        if event.is_a?(Termisu::Event::Key)
          event.key.should eq(Termisu::Input::Key::LowerA)
          event.alt?.should be_true
        end
      end

      it "parses Alt+A (\\eA)" do
        event = parse_sequence(Bytes[0x1B, 'A'.ord])
        event.should be_a(Termisu::Event::Key)
        if event.is_a?(Termisu::Event::Key)
          event.key.should eq(Termisu::Input::Key::UpperA)
          event.alt?.should be_true
        end
      end

      it "parses Alt+5 (\\e5)" do
        event = parse_sequence(Bytes[0x1B, '5'.ord])
        event.should be_a(Termisu::Event::Key)
        if event.is_a?(Termisu::Event::Key)
          event.key.should eq(Termisu::Input::Key::Num5)
          event.alt?.should be_true
        end
      end
    end

    context "SGR mouse protocol" do
      it "parses left click (\\e[<0;10;20M)" do
        # ESC [ < 0 ; 10 ; 20 M
        seq = "\e[<0;10;20M".to_slice
        event = parse_sequence(seq)
        event.should be_a(Termisu::Event::Mouse)
        if event.is_a?(Termisu::Event::Mouse)
          event.x.should eq(10)
          event.y.should eq(20)
          event.button.should eq(Termisu::Event::Mouse::Button::Left)
        end
      end

      it "parses middle click (\\e[<1;5;5M)" do
        seq = "\e[<1;5;5M".to_slice
        event = parse_sequence(seq)
        event.should be_a(Termisu::Event::Mouse)
        if event.is_a?(Termisu::Event::Mouse)
          event.button.should eq(Termisu::Event::Mouse::Button::Middle)
        end
      end

      it "parses right click (\\e[<2;5;5M)" do
        seq = "\e[<2;5;5M".to_slice
        event = parse_sequence(seq)
        event.should be_a(Termisu::Event::Mouse)
        if event.is_a?(Termisu::Event::Mouse)
          event.button.should eq(Termisu::Event::Mouse::Button::Right)
        end
      end

      it "parses release (\\e[<0;10;20m)" do
        # lowercase 'm' indicates release
        seq = "\e[<0;10;20m".to_slice
        event = parse_sequence(seq)
        event.should be_a(Termisu::Event::Mouse)
        if event.is_a?(Termisu::Event::Mouse)
          event.button.should eq(Termisu::Event::Mouse::Button::Release)
        end
      end

      it "parses wheel up (\\e[<64;10;10M)" do
        seq = "\e[<64;10;10M".to_slice
        event = parse_sequence(seq)
        event.should be_a(Termisu::Event::Mouse)
        if event.is_a?(Termisu::Event::Mouse)
          event.button.should eq(Termisu::Event::Mouse::Button::WheelUp)
          event.wheel?.should be_true
        end
      end

      it "parses wheel down (\\e[<65;10;10M)" do
        seq = "\e[<65;10;10M".to_slice
        event = parse_sequence(seq)
        event.should be_a(Termisu::Event::Mouse)
        if event.is_a?(Termisu::Event::Mouse)
          event.button.should eq(Termisu::Event::Mouse::Button::WheelDown)
        end
      end

      it "parses click with Shift modifier (\\e[<4;10;10M)" do
        seq = "\e[<4;10;10M".to_slice
        event = parse_sequence(seq)
        event.should be_a(Termisu::Event::Mouse)
        if event.is_a?(Termisu::Event::Mouse)
          event.shift?.should be_true
        end
      end

      it "parses click with Ctrl modifier (\\e[<16;10;10M)" do
        seq = "\e[<16;10;10M".to_slice
        event = parse_sequence(seq)
        event.should be_a(Termisu::Event::Mouse)
        if event.is_a?(Termisu::Event::Mouse)
          event.ctrl?.should be_true
        end
      end

      it "parses motion event (\\e[<32;15;25M)" do
        seq = "\e[<32;15;25M".to_slice
        event = parse_sequence(seq)
        event.should be_a(Termisu::Event::Mouse)
        if event.is_a?(Termisu::Event::Mouse)
          event.motion?.should be_true
        end
      end

      it "parses large coordinates" do
        seq = "\e[<0;500;1000M".to_slice
        event = parse_sequence(seq)
        event.should be_a(Termisu::Event::Mouse)
        if event.is_a?(Termisu::Event::Mouse)
          event.x.should eq(500)
          event.y.should eq(1000)
        end
      end

      it "aborts overlong SGR sequences with Key::Unknown" do
        seq = ("\e[<" + "9" * 40 + "M").to_slice
        event = parse_sequence(seq)
        event.should be_a(Termisu::Event::Key)
        if event.is_a?(Termisu::Event::Key)
          event.key.should eq(Termisu::Input::Key::Unknown)
        end
      end

      it "rejects malformed non-ASCII coordinate params (\\e[<0;\\xC3;5M)" do
        seq = Bytes[0x1B, '['.ord, '<'.ord, '0'.ord, ';'.ord, 0xC3, ';'.ord, '5'.ord, 'M'.ord]
        event = parse_sequence(seq)
        # A coordinate that fails to_i? must not fabricate a mouse event.
        event.should be_a(Termisu::Event::Key)
        if event.is_a?(Termisu::Event::Key)
          event.key.should eq(Termisu::Input::Key::Unknown)
        end
      end
    end

    context "normal mouse protocol" do
      it "parses left click at 1,1" do
        # ESC [ M Cb Cx Cy (each + 32)
        # Left click at 1,1: cb=32, cx=33, cy=33
        seq = Bytes[0x1B, '['.ord, 'M'.ord, 32, 33, 33]
        event = parse_sequence(seq)
        event.should be_a(Termisu::Event::Mouse)
        if event.is_a?(Termisu::Event::Mouse)
          event.button.should eq(Termisu::Event::Mouse::Button::Left)
          event.x.should eq(1)
          event.y.should eq(1)
        end
      end

      it "parses right click at 50,25" do
        # Right click (cb=2): 2+32=34, x=50+32=82, y=25+32=57
        seq = Bytes[0x1B, '['.ord, 'M'.ord, 34, 82, 57]
        event = parse_sequence(seq)
        event.should be_a(Termisu::Event::Mouse)
        if event.is_a?(Termisu::Event::Mouse)
          event.button.should eq(Termisu::Event::Mouse::Button::Right)
          event.x.should eq(50)
          event.y.should eq(25)
        end
      end

      it "parses release" do
        # Release (cb=3): 3+32=35
        seq = Bytes[0x1B, '['.ord, 'M'.ord, 35, 33, 33]
        event = parse_sequence(seq)
        event.should be_a(Termisu::Event::Mouse)
        if event.is_a?(Termisu::Event::Mouse)
          event.button.should eq(Termisu::Event::Mouse::Button::Release)
        end
      end

      it "parses wheel up" do
        # Wheel up (cb=64): 64+32=96
        seq = Bytes[0x1B, '['.ord, 'M'.ord, 96, 33, 33]
        event = parse_sequence(seq)
        event.should be_a(Termisu::Event::Mouse)
        if event.is_a?(Termisu::Event::Mouse)
          event.button.should eq(Termisu::Event::Mouse::Button::WheelUp)
        end
      end

      it "clamps coordinates to valid range" do
        # Coordinates that would go negative after -32 should be clamped
        seq = Bytes[0x1B, '['.ord, 'M'.ord, 32, 31, 31] # Would be -1, -1
        event = parse_sequence(seq)
        event.should be_a(Termisu::Event::Mouse)
        if event.is_a?(Termisu::Event::Mouse)
          event.x.should be >= 1
          event.y.should be >= 1
        end
      end
    end

    context "parser deadlines" do
      it "parses complete buffered sequences nonblockingly across every read boundary" do
        utf8 = parse_sequence_with_buffer("€".to_slice, 1, 0)
        utf8.should be_a(Termisu::Event::Key)
        utf8.as(Termisu::Event::Key).char.should eq('€')

        csi_u = parse_sequence_with_buffer("\e[97;1u".to_slice, 1, 0)
        csi_u.should be_a(Termisu::Event::Key)
        csi_u.as(Termisu::Event::Key).key.should eq(Termisu::Input::Key::LowerA)

        ss3 = parse_sequence_with_buffer("\eOP".to_slice, 1, 0)
        ss3.should be_a(Termisu::Event::Key)
        ss3.as(Termisu::Event::Key).key.should eq(Termisu::Input::Key::F1)

        sgr_mouse = parse_sequence_with_buffer("\e[<0;1;1M".to_slice, 1, 0)
        sgr_mouse.should be_a(Termisu::Event::Mouse)

        normal_mouse = parse_sequence_with_buffer(Bytes[0x1B, '['.ord, 'M'.ord, 32, 33, 33], 1, 0)
        normal_mouse.should be_a(Termisu::Event::Mouse)
      end

      it "uses one deadline when continuation bytes drip in" do
        reader = ParserDripReader.new("\e[1234A".to_slice, gap_ms: 4)
        parser = ParserDripProbe.new(reader)

        event = parser.poll_event(10)

        event.should be_a(Termisu::Event::Key)
        event.as(Termisu::Event::Key).key.should eq(Termisu::Input::Key::Unknown)
        reader.consumed.should eq(3)
        reader.elapsed.should eq(10.milliseconds)
      end

      it "bounds every truncated continuation path by one poll timeout" do
        sequences = {
          "UTF-8"        => Bytes[0xF0, 0x9F],
          "Alt UTF-8"    => Bytes[0x1B, 0xC3],
          "CSI"          => "\e[1;".to_slice,
          "Kitty CSI-u"  => "\e[97;1".to_slice,
          "SS3"          => "\eO".to_slice,
          "SGR mouse"    => "\e[<0;1".to_slice,
          "normal mouse" => Bytes[0x1B, '['.ord, 'M'.ord, 32],
        }

        sequences.each do |name, bytes|
          read_fd, write_fd = create_pipe
          begin
            LibC.write(write_fd, bytes, bytes.size)
            reader = Termisu::Reader.new(read_fd)
            parser = Termisu::Input::Parser.new(reader)

            elapsed = Time.measure do
              event = parser.poll_event(10)
              event.should be_a(Termisu::Event::Key), name
              event.as(Termisu::Event::Key).key.should eq(Termisu::Input::Key::Unknown), name
            end
            elapsed.should be < 250.milliseconds, name
          ensure
            reader.try(&.close)
            LibC.close(read_fd)
            LibC.close(write_fd)
          end
        end
      end
    end

    context "timeout handling" do
      it "returns nil on empty input" do
        read_fd, write_fd = create_pipe
        begin
          # Set non-blocking
          flags = LibC.fcntl(read_fd, LibC::F_GETFL, 0)
          LibC.fcntl(read_fd, LibC::F_SETFL, flags | LibC::O_NONBLOCK)

          reader = Termisu::Reader.new(read_fd)
          parser = Termisu::Input::Parser.new(reader)
          event = parser.poll_event(10)
          event.should be_nil
          reader.close
        ensure
          LibC.close(read_fd)
          LibC.close(write_fd)
        end
      end
    end
  end
end

# Drives the parser over a single byte stream, polling `count` events. Used to
# exercise the interaction between a Kitty CSI-u text report and the raw-byte
# path that immediately follows it, and by the bracketed-paste specs, where a
# paste is only meaningful as a sequence of events rather than one at a time.
private def parse_events(bytes : Bytes, count : Int32) : Array(Termisu::Event::Any?)
  read_fd, write_fd = create_pipe
  events = [] of Termisu::Event::Any?
  begin
    LibC.write(write_fd, bytes, bytes.size)
    reader = Termisu::Reader.new(read_fd)
    parser = Termisu::Input::Parser.new(reader)
    count.times { events << parser.poll_event(100) }
  ensure
    reader.try(&.close)
    LibC.close(read_fd)
    LibC.close(write_fd)
  end
  events
end

describe Termisu::Input::Parser do
  describe "Kitty report_text (CSI >17u) + raw printable bytes" do
    # Under flags 17u (disambiguate + report_text, NO report_all_keys), modified
    # keys arrive as CSI-u while plain unmodified keys still arrive as raw bytes.
    # A text-bearing CSI-u event must NOT cause subsequent plain raw keys to be
    # dropped — only an exact duplicate echo of that one char is a duplicate.
    it "keeps plain raw keys typed after a CSI-u text event" do
      # Shift+a -> 'A' (codepoint 97, shift mod 2, text 65), then raw "bc".
      bytes = Bytes[0x1B, '['.ord, '9'.ord, '7'.ord, ';'.ord, '2'.ord, ';'.ord, '6'.ord, '5'.ord, 'u'.ord,
        'b'.ord, 'c'.ord]
      events = parse_events(bytes, 3)
      events[0].as(Termisu::Event::Key).char.should eq('A')
      events[1].as(Termisu::Event::Key).char.should eq('b')
      events[2].as(Termisu::Event::Key).char.should eq('c')
    end

    it "drops only an exact duplicate raw echo of the CSI-u char" do
      # CSI-u 'x' (codepoint 120, text 120), then raw 'x' (the echo), then raw 'y'.
      bytes = Bytes[0x1B, '['.ord, '1'.ord, '2'.ord, '0'.ord, ';'.ord, '1'.ord, ';'.ord, '1'.ord, '2'.ord, '0'.ord, 'u'.ord,
        'x'.ord, 'y'.ord]
      events = parse_events(bytes, 3)
      events[0].as(Termisu::Event::Key).char.should eq('x')
      # the duplicate echo is swallowed (Unknown, no char)
      events[1].as(Termisu::Event::Key).char.should be_nil
      events[2].as(Termisu::Event::Key).char.should eq('y')
    end

    # A modified key arrives as CSI-u with an EMPTY text field, so `c` falls back
    # to the codepoint and Ctrl+P yields c == 'p'. The terminal sends Ctrl+P as
    # the control byte 0x10 and never as a raw 'p', so such a report must not arm
    # the dup guard — otherwise it eats the next plain 'p' the user types.
    it "keeps a plain key typed right after the same letter under Ctrl" do
      # Ctrl+p -> CSI 112;5u (no text field), then raw "pet".
      bytes = Bytes[0x1B, '['.ord, '1'.ord, '1'.ord, '2'.ord, ';'.ord, '5'.ord, 'u'.ord,
        'p'.ord, 'e'.ord, 't'.ord]
      events = parse_events(bytes, 4)
      events[0].as(Termisu::Event::Key).modifiers.ctrl?.should be_true
      events[1].as(Termisu::Event::Key).char.should eq('p')
      events[2].as(Termisu::Event::Key).char.should eq('e')
      events[3].as(Termisu::Event::Key).char.should eq('t')
    end

    it "keeps a plain key typed right after the same letter under Alt" do
      # Alt+p -> CSI 112;3u, then raw 'p'.
      bytes = Bytes[0x1B, '['.ord, '1'.ord, '1'.ord, '2'.ord, ';'.ord, '3'.ord, 'u'.ord,
        'p'.ord]
      events = parse_events(bytes, 2)
      events[0].as(Termisu::Event::Key).modifiers.alt?.should be_true
      events[1].as(Termisu::Event::Key).char.should eq('p')
    end

    it "keeps a plain key typed right after the same letter under modifyOtherKeys Ctrl" do
      # Ctrl+p via modifyOtherKeys -> CSI 27;5;112~, then raw 'p'.
      bytes = Bytes[0x1B, '['.ord, '2'.ord, '7'.ord, ';'.ord, '5'.ord, ';'.ord,
        '1'.ord, '1'.ord, '2'.ord, '~'.ord,
        'p'.ord]
      events = parse_events(bytes, 2)
      events[0].as(Termisu::Event::Key).modifiers.ctrl?.should be_true
      events[1].as(Termisu::Event::Key).char.should eq('p')
    end
  end
end

describe Termisu::Input::Parser do
  describe "Kitty CSI-u text field parsing" do
    it "keeps all codepoints of a multi-codepoint text field (no ':' truncation)" do
      # CSI 0;1;4352:4449 u -> pure-text (preedit) event carrying two Hangul jamo.
      bytes = Bytes[0x1B, '['.ord, '0'.ord, ';'.ord, '1'.ord, ';'.ord,
        '4'.ord, '3'.ord, '5'.ord, '2'.ord, ':'.ord, '4'.ord, '4'.ord, '4'.ord, '9'.ord, 'u'.ord]
      event = parse_sequence(bytes)
      event.should be_a(Termisu::Event::Preedit)
      event.as(Termisu::Event::Preedit).text.size.should eq(2)
    end

    it "emits Preedit with empty text for a codepoint-0 report with no text (preedit cleared)" do
      # CSI 0;1 u -> terminal signalling composition cleared.
      bytes = Bytes[0x1B, '['.ord, '0'.ord, ';'.ord, '1'.ord, 'u'.ord]
      event = parse_sequence(bytes)
      event.should be_a(Termisu::Event::Preedit)
      event.as(Termisu::Event::Preedit).text.empty?.should be_true
    end

    it "parses an event-type in the modifier field without dropping the key" do
      # CSI 97;5:1 u -> Ctrl+a press (mods=5, event_type=1); the ':' is the event type.
      bytes = Bytes[0x1B, '['.ord, '9'.ord, '7'.ord, ';'.ord, '5'.ord, ':'.ord, '1'.ord, 'u'.ord]
      event = parse_sequence(bytes)
      event.should be_a(Termisu::Event::Key)
      if event.is_a?(Termisu::Event::Key)
        event.char.should eq('a')
        event.modifiers.ctrl?.should be_true
      end
    end
  end
end
