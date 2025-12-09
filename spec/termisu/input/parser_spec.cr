require "../../spec_helper"

# Helper to create a pipe
private def create_pipe : {Int32, Int32}
  fds = uninitialized StaticArray(Int32, 2)
  result = LibC.pipe(fds)
  raise "pipe() failed" if result != 0
  {fds[0], fds[1]}
end

# Helper to write bytes to pipe and parse event
private def parse_sequence(bytes : Bytes) : Termisu::Event::Any?
  read_fd, write_fd = create_pipe
  reader = nil
  begin
    LibC.write(write_fd, bytes, bytes.size)
    reader = Termisu::Reader.new(read_fd)
    parser = Termisu::Input::Parser.new(reader)
    parser.poll_event(100)
  ensure
    reader.try(&.close)
    LibC.close(read_fd)
    LibC.close(write_fd)
  end
end

# Ensure LibC has required functions
lib LibC
  {% unless LibC.has_method?(:pipe) %}
    fun pipe(fds : Int32*) : Int32
  {% end %}

  {% unless LibC.has_method?(:fcntl) %}
    fun fcntl(fd : Int32, cmd : Int32, arg : Int32) : Int32
  {% end %}

  {% unless LibC.has_method?(:write) %}
    fun write(fd : Int32, buf : UInt8*, count : LibC::SizeT) : LibC::SSizeT
  {% end %}
end

describe Termisu::Input::Parser do
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
          event.button.should eq(Termisu::Event::MouseButton::Left)
        end
      end

      it "parses middle click (\\e[<1;5;5M)" do
        seq = "\e[<1;5;5M".to_slice
        event = parse_sequence(seq)
        event.should be_a(Termisu::Event::Mouse)
        if event.is_a?(Termisu::Event::Mouse)
          event.button.should eq(Termisu::Event::MouseButton::Middle)
        end
      end

      it "parses right click (\\e[<2;5;5M)" do
        seq = "\e[<2;5;5M".to_slice
        event = parse_sequence(seq)
        event.should be_a(Termisu::Event::Mouse)
        if event.is_a?(Termisu::Event::Mouse)
          event.button.should eq(Termisu::Event::MouseButton::Right)
        end
      end

      it "parses release (\\e[<0;10;20m)" do
        # lowercase 'm' indicates release
        seq = "\e[<0;10;20m".to_slice
        event = parse_sequence(seq)
        event.should be_a(Termisu::Event::Mouse)
        if event.is_a?(Termisu::Event::Mouse)
          event.button.should eq(Termisu::Event::MouseButton::Release)
        end
      end

      it "parses wheel up (\\e[<64;10;10M)" do
        seq = "\e[<64;10;10M".to_slice
        event = parse_sequence(seq)
        event.should be_a(Termisu::Event::Mouse)
        if event.is_a?(Termisu::Event::Mouse)
          event.button.should eq(Termisu::Event::MouseButton::WheelUp)
          event.wheel?.should be_true
        end
      end

      it "parses wheel down (\\e[<65;10;10M)" do
        seq = "\e[<65;10;10M".to_slice
        event = parse_sequence(seq)
        event.should be_a(Termisu::Event::Mouse)
        if event.is_a?(Termisu::Event::Mouse)
          event.button.should eq(Termisu::Event::MouseButton::WheelDown)
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
    end

    context "normal mouse protocol" do
      it "parses left click at 1,1" do
        # ESC [ M Cb Cx Cy (each + 32)
        # Left click at 1,1: cb=32, cx=33, cy=33
        seq = Bytes[0x1B, '['.ord, 'M'.ord, 32, 33, 33]
        event = parse_sequence(seq)
        event.should be_a(Termisu::Event::Mouse)
        if event.is_a?(Termisu::Event::Mouse)
          event.button.should eq(Termisu::Event::MouseButton::Left)
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
          event.button.should eq(Termisu::Event::MouseButton::Right)
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
          event.button.should eq(Termisu::Event::MouseButton::Release)
        end
      end

      it "parses wheel up" do
        # Wheel up (cb=64): 64+32=96
        seq = Bytes[0x1B, '['.ord, 'M'.ord, 96, 33, 33]
        event = parse_sequence(seq)
        event.should be_a(Termisu::Event::Mouse)
        if event.is_a?(Termisu::Event::Mouse)
          event.button.should eq(Termisu::Event::MouseButton::WheelUp)
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
