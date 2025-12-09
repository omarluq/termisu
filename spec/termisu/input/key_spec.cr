require "../../spec_helper"

describe Termisu::Input::Key do
  describe ".from_char" do
    context "uppercase letters A-Z" do
      it "maps 'A' to UpperA" do
        Termisu::Input::Key.from_char('A').should eq(Termisu::Input::Key::UpperA)
      end

      it "maps 'Z' to UpperZ" do
        Termisu::Input::Key.from_char('Z').should eq(Termisu::Input::Key::UpperZ)
      end

      it "maps 'M' to UpperM" do
        Termisu::Input::Key.from_char('M').should eq(Termisu::Input::Key::UpperM)
      end
    end

    context "lowercase letters a-z" do
      it "maps 'a' to LowerA" do
        Termisu::Input::Key.from_char('a').should eq(Termisu::Input::Key::LowerA)
      end

      it "maps 'z' to LowerZ" do
        Termisu::Input::Key.from_char('z').should eq(Termisu::Input::Key::LowerZ)
      end

      it "maps 'm' to LowerM" do
        Termisu::Input::Key.from_char('m').should eq(Termisu::Input::Key::LowerM)
      end
    end

    context "digits 0-9" do
      it "maps '0' to Num0" do
        Termisu::Input::Key.from_char('0').should eq(Termisu::Input::Key::Num0)
      end

      it "maps '9' to Num9" do
        Termisu::Input::Key.from_char('9').should eq(Termisu::Input::Key::Num9)
      end

      it "maps '5' to Num5" do
        Termisu::Input::Key.from_char('5').should eq(Termisu::Input::Key::Num5)
      end
    end

    context "punctuation and symbols" do
      it "maps '`' to Backtick" do
        Termisu::Input::Key.from_char('`').should eq(Termisu::Input::Key::Backtick)
      end

      it "maps '-' to Minus" do
        Termisu::Input::Key.from_char('-').should eq(Termisu::Input::Key::Minus)
      end

      it "maps '=' to Equals" do
        Termisu::Input::Key.from_char('=').should eq(Termisu::Input::Key::Equals)
      end

      it "maps '[' to LeftBracket" do
        Termisu::Input::Key.from_char('[').should eq(Termisu::Input::Key::LeftBracket)
      end

      it "maps ']' to RightBracket" do
        Termisu::Input::Key.from_char(']').should eq(Termisu::Input::Key::RightBracket)
      end

      it "maps '\\' to Backslash" do
        Termisu::Input::Key.from_char('\\').should eq(Termisu::Input::Key::Backslash)
      end

      it "maps ';' to Semicolon" do
        Termisu::Input::Key.from_char(';').should eq(Termisu::Input::Key::Semicolon)
      end

      it "maps '\\'' to Quote" do
        Termisu::Input::Key.from_char('\'').should eq(Termisu::Input::Key::Quote)
      end

      it "maps ',' to Comma" do
        Termisu::Input::Key.from_char(',').should eq(Termisu::Input::Key::Comma)
      end

      it "maps '.' to Period" do
        Termisu::Input::Key.from_char('.').should eq(Termisu::Input::Key::Period)
      end

      it "maps '/' to Slash" do
        Termisu::Input::Key.from_char('/').should eq(Termisu::Input::Key::Slash)
      end
    end

    context "shifted symbols" do
      it "maps '~' to Tilde" do
        Termisu::Input::Key.from_char('~').should eq(Termisu::Input::Key::Tilde)
      end

      it "maps '!' to Exclaim" do
        Termisu::Input::Key.from_char('!').should eq(Termisu::Input::Key::Exclaim)
      end

      it "maps '@' to At" do
        Termisu::Input::Key.from_char('@').should eq(Termisu::Input::Key::At)
      end

      it "maps '#' to Hash" do
        Termisu::Input::Key.from_char('#').should eq(Termisu::Input::Key::Hash)
      end

      it "maps '$' to Dollar" do
        Termisu::Input::Key.from_char('$').should eq(Termisu::Input::Key::Dollar)
      end

      it "maps '%' to Percent" do
        Termisu::Input::Key.from_char('%').should eq(Termisu::Input::Key::Percent)
      end

      it "maps '^' to Caret" do
        Termisu::Input::Key.from_char('^').should eq(Termisu::Input::Key::Caret)
      end

      it "maps '&' to Ampersand" do
        Termisu::Input::Key.from_char('&').should eq(Termisu::Input::Key::Ampersand)
      end

      it "maps '*' to Asterisk" do
        Termisu::Input::Key.from_char('*').should eq(Termisu::Input::Key::Asterisk)
      end

      it "maps '(' to LeftParen" do
        Termisu::Input::Key.from_char('(').should eq(Termisu::Input::Key::LeftParen)
      end

      it "maps ')' to RightParen" do
        Termisu::Input::Key.from_char(')').should eq(Termisu::Input::Key::RightParen)
      end

      it "maps '_' to Underscore" do
        Termisu::Input::Key.from_char('_').should eq(Termisu::Input::Key::Underscore)
      end

      it "maps '+' to Plus" do
        Termisu::Input::Key.from_char('+').should eq(Termisu::Input::Key::Plus)
      end

      it "maps '{' to LeftBrace" do
        Termisu::Input::Key.from_char('{').should eq(Termisu::Input::Key::LeftBrace)
      end

      it "maps '}' to RightBrace" do
        Termisu::Input::Key.from_char('}').should eq(Termisu::Input::Key::RightBrace)
      end

      it "maps '|' to Pipe" do
        Termisu::Input::Key.from_char('|').should eq(Termisu::Input::Key::Pipe)
      end

      it "maps ':' to Colon" do
        Termisu::Input::Key.from_char(':').should eq(Termisu::Input::Key::Colon)
      end

      it "maps '\"' to DoubleQuote" do
        Termisu::Input::Key.from_char('"').should eq(Termisu::Input::Key::DoubleQuote)
      end

      it "maps '<' to LessThan" do
        Termisu::Input::Key.from_char('<').should eq(Termisu::Input::Key::LessThan)
      end

      it "maps '>' to GreaterThan" do
        Termisu::Input::Key.from_char('>').should eq(Termisu::Input::Key::GreaterThan)
      end

      it "maps '?' to Question" do
        Termisu::Input::Key.from_char('?').should eq(Termisu::Input::Key::Question)
      end
    end

    context "whitespace and control" do
      it "maps ' ' to Space" do
        Termisu::Input::Key.from_char(' ').should eq(Termisu::Input::Key::Space)
      end

      it "maps '\\t' to Tab" do
        Termisu::Input::Key.from_char('\t').should eq(Termisu::Input::Key::Tab)
      end

      it "maps '\\n' to Enter" do
        Termisu::Input::Key.from_char('\n').should eq(Termisu::Input::Key::Enter)
      end

      it "maps '\\r' to Enter" do
        Termisu::Input::Key.from_char('\r').should eq(Termisu::Input::Key::Enter)
      end
    end

    context "unknown characters" do
      it "maps unmapped characters to Unknown" do
        Termisu::Input::Key.from_char('\u{00}').should eq(Termisu::Input::Key::Unknown)
      end
    end
  end

  describe "#to_char" do
    context "uppercase letters" do
      it "converts UpperA to 'A'" do
        Termisu::Input::Key::UpperA.to_char.should eq('A')
      end

      it "converts UpperZ to 'Z'" do
        Termisu::Input::Key::UpperZ.to_char.should eq('Z')
      end
    end

    context "lowercase letters" do
      it "converts LowerA to 'a'" do
        Termisu::Input::Key::LowerA.to_char.should eq('a')
      end

      it "converts LowerZ to 'z'" do
        Termisu::Input::Key::LowerZ.to_char.should eq('z')
      end
    end

    context "digits" do
      it "converts Num0 to '0'" do
        Termisu::Input::Key::Num0.to_char.should eq('0')
      end

      it "converts Num9 to '9'" do
        Termisu::Input::Key::Num9.to_char.should eq('9')
      end
    end

    context "symbols" do
      it "converts Backtick to '`'" do
        Termisu::Input::Key::Backtick.to_char.should eq('`')
      end

      it "converts Space to ' '" do
        Termisu::Input::Key::Space.to_char.should eq(' ')
      end

      it "converts Enter to '\\n'" do
        Termisu::Input::Key::Enter.to_char.should eq('\n')
      end
    end

    context "non-printable keys" do
      it "returns nil for Up" do
        Termisu::Input::Key::Up.to_char.should be_nil
      end

      it "returns nil for F1" do
        Termisu::Input::Key::F1.to_char.should be_nil
      end

      it "returns nil for Home" do
        Termisu::Input::Key::Home.to_char.should be_nil
      end

      it "returns nil for Unknown" do
        Termisu::Input::Key::Unknown.to_char.should be_nil
      end

      it "returns nil for Escape" do
        Termisu::Input::Key::Escape.to_char.should be_nil
      end

      it "returns nil for Backspace" do
        Termisu::Input::Key::Backspace.to_char.should be_nil
      end
    end
  end

  describe "#letter?" do
    it "returns true for uppercase letters" do
      Termisu::Input::Key::UpperA.letter?.should be_true
      Termisu::Input::Key::UpperZ.letter?.should be_true
      Termisu::Input::Key::UpperM.letter?.should be_true
    end

    it "returns true for lowercase letters" do
      Termisu::Input::Key::LowerA.letter?.should be_true
      Termisu::Input::Key::LowerZ.letter?.should be_true
      Termisu::Input::Key::LowerM.letter?.should be_true
    end

    it "returns false for non-letters" do
      Termisu::Input::Key::Num0.letter?.should be_false
      Termisu::Input::Key::Space.letter?.should be_false
      Termisu::Input::Key::F1.letter?.should be_false
    end
  end

  describe "#digit?" do
    it "returns true for digits" do
      Termisu::Input::Key::Num0.digit?.should be_true
      Termisu::Input::Key::Num5.digit?.should be_true
      Termisu::Input::Key::Num9.digit?.should be_true
    end

    it "returns false for non-digits" do
      Termisu::Input::Key::LowerA.digit?.should be_false
      Termisu::Input::Key::Space.digit?.should be_false
      Termisu::Input::Key::F1.digit?.should be_false
    end
  end

  describe "#function_key?" do
    it "returns true for function keys F1-F24" do
      Termisu::Input::Key::F1.function_key?.should be_true
      Termisu::Input::Key::F12.function_key?.should be_true
      Termisu::Input::Key::F24.function_key?.should be_true
    end

    it "returns false for non-function keys" do
      Termisu::Input::Key::LowerA.function_key?.should be_false
      Termisu::Input::Key::Up.function_key?.should be_false
      Termisu::Input::Key::Escape.function_key?.should be_false
    end
  end

  describe "#navigation?" do
    it "returns true for arrow keys" do
      Termisu::Input::Key::Up.navigation?.should be_true
      Termisu::Input::Key::Down.navigation?.should be_true
      Termisu::Input::Key::Left.navigation?.should be_true
      Termisu::Input::Key::Right.navigation?.should be_true
    end

    it "returns true for navigation keys" do
      Termisu::Input::Key::Home.navigation?.should be_true
      Termisu::Input::Key::End.navigation?.should be_true
      Termisu::Input::Key::PageUp.navigation?.should be_true
      Termisu::Input::Key::PageDown.navigation?.should be_true
    end

    it "returns false for non-navigation keys" do
      Termisu::Input::Key::LowerA.navigation?.should be_false
      Termisu::Input::Key::F1.navigation?.should be_false
      Termisu::Input::Key::Space.navigation?.should be_false
    end
  end

  describe "#printable?" do
    it "returns true for printable keys" do
      Termisu::Input::Key::LowerA.printable?.should be_true
      Termisu::Input::Key::UpperA.printable?.should be_true
      Termisu::Input::Key::Num5.printable?.should be_true
      Termisu::Input::Key::Space.printable?.should be_true
    end

    it "returns false for non-printable keys" do
      Termisu::Input::Key::Up.printable?.should be_false
      Termisu::Input::Key::F1.printable?.should be_false
      Termisu::Input::Key::Escape.printable?.should be_false
      Termisu::Input::Key::Unknown.printable?.should be_false
    end
  end

  describe "roundtrip conversion" do
    it "from_char -> to_char roundtrips for printable chars" do
      printable_chars = ('A'..'Z').to_a + ('a'..'z').to_a + ('0'..'9').to_a
      printable_chars << ' '
      printable_chars << '-'
      printable_chars << '='

      printable_chars.each do |char|
        key = Termisu::Input::Key.from_char(char)
        key.to_char.should eq(char), "roundtrip failed for '#{char}'"
      end
    end
  end
end
