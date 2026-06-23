require "./e2e_helper"

# Port of e2e/tests/keyboard.test.ts — drives bin/kmd and asserts on the
# "Last event:" readout for each input type.
private def with_kmd(&)
  requires_binary "bin/kmd"
  Termisu::Testing.terminal("bin/kmd", cols: 100, rows: 50) do |term|
    term.get_by_text("Esc").should be_true # layout rendered
    yield term
  end
end

describe "Keyboard & Mouse demo (e2e)" do
  describe "layout rendering" do
    it "displays the demo title" do
      with_kmd do |term|
        term.get_by_text(/KEYBOARD.*MOUSE.*DEMO/).should be_true
      end
    end

    it "renders keyboard rows and modifiers" do
      with_kmd do |term|
        term.get_by_text("Esc").should be_true
        term.get_by_text("Ctrl").should be_true
        term.get_by_text("Alt").should be_true
        term.get_by_text("Q").should be_true
        term.get_by_text("W").should be_true
      end
    end

    it "shows the mouse info panel and quit hint" do
      with_kmd do |term|
        term.get_by_text(/Mouse:/).should be_true
        term.get_by_text(/Position:/).should be_true
        term.get_by_text(/ESC.*Ctrl.*C.*quit/).should be_true
      end
    end
  end

  describe "letter keys" do
    {"a" => "LowerA", "z" => "LowerZ", "A" => "UpperA", "Z" => "UpperZ"}.each do |input, name|
      it "detects #{input}" do
        with_kmd do |term|
          term.write(input)
          term.get_by_text(/Last event:.*#{name}/).should be_true
        end
      end
    end
  end

  describe "number and symbol keys" do
    {"1" => "Num1", "0" => "Num0", "!" => "Exclaim", "@" => "At", "#" => "Hash"}.each do |input, name|
      it "detects #{input}" do
        with_kmd do |term|
          term.write(input)
          term.get_by_text(/Last event:.*#{name}/).should be_true
        end
      end
    end
  end

  describe "punctuation and bracket keys" do
    {"," => "Comma", "." => "Period", "/" => "Slash", ";" => "Semicolon",
     "[" => "LeftBracket", "]" => "RightBracket", "{" => "LeftBrace", "}" => "RightBrace"}.each do |input, name|
      it "detects #{name}" do
        with_kmd do |term|
          term.write(input)
          term.get_by_text(/Last event:.*#{name}/).should be_true
        end
      end
    end
  end

  describe "special keys" do
    it "detects Tab" do
      with_kmd { |term| term.key(:tab); term.get_by_text(/Last event:.*Tab/).should be_true }
    end

    it "detects Enter" do
      with_kmd { |term| term.key(:enter); term.get_by_text(/Last event:.*Enter/).should be_true }
    end

    it "detects Backspace" do
      with_kmd { |term| term.key(:backspace); term.get_by_text(/Last event:.*Backspace/).should be_true }
    end

    it "detects Space" do
      with_kmd { |term| term.key(:space); term.get_by_text(/Last event:.*Space/).should be_true }
    end
  end

  describe "arrow keys" do
    {up: "Up", down: "Down", left: "Left", right: "Right"}.each do |sym, name|
      it "detects #{name} arrow" do
        with_kmd do |term|
          term.key(sym)
          term.get_by_text(/Last event:.*#{name}/).should be_true
        end
      end
    end
  end

  describe "mouse events" do
    it "detects wheel scroll up" do
      with_kmd do |term|
        term.write("\e[<64;15;8M") # SGR mouse: button 64 = wheel up
        term.get_by_text("WheelUp").should be_true
      end
    end

    it "detects wheel scroll down" do
      with_kmd do |term|
        term.write("\e[<65;15;8M") # button 65 = wheel down
        term.get_by_text("WheelDown").should be_true
      end
    end
  end

  describe "layout snapshot" do
    it "matches the initial keyboard-layout snapshot" do
      with_kmd { |term| assert_snapshot(term, "keyboard") }
    end
  end

  describe "exit handling" do
    it "exits on ESC without hanging" do
      with_kmd do |term|
        term.key(:esc)
        # block exit + close must not hang
      end
    end

    it "exits on Ctrl+C without hanging" do
      with_kmd do |term|
        term.ctrl('c')
      end
    end
  end
end
