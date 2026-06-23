require "./e2e_helper"

# Exercises the Terminal harness + PTY layer against a tiny shell program rather
# than a compiled example, so these paths are covered even in builds that don't
# build the examples (e.g. the coverage build). /bin/sh exists on every target,
# and `printf` emits the escape sequences the emulator parses.
describe Termisu::Testing::Terminal do
  it "captures output and reports cursor, position, row and snapshot" do
    Termisu::Testing.terminal(
      "/bin/sh", ["-c", "printf '\\033[2J\\033[3;5HHELLO'; sleep 2"],
      cols: 40, rows: 10,
    ) do |term|
      term.get_by_text("HELLO").should be_true
      term.locate("HELLO").should eq({4, 2}) # row 3, col 5 (1-based) -> {4, 2}
      term.find("HELLO").should eq({4, 2})
      term.find("MISSING").should be_nil
      term.row(2).should contain("HELLO")
      term.cursor.should eq({9, 2}) # cursor sits just past "HELLO"
      term.snapshot.should contain("HELLO")
    end
  end

  it "sends input, special keys, and resizes the terminal" do
    Termisu::Testing.terminal("/bin/sh", ["-c", "sleep 2"], cols: 20, rows: 5) do |term|
      term.write("hello")
      term.key_press('q')
      term.key(:up)
      term.resize(30, 8)
      term.ctrl('c')
      expect_raises(ArgumentError) { term.key(:no_such_key) }
    end
  end

  it "returns false when text never appears before the timeout" do
    Termisu::Testing.terminal("/bin/sh", ["-c", "sleep 2"], cols: 20, rows: 3) do |term|
      term.get_by_text("WILL_NOT_APPEAR", timeout: 200.milliseconds).should be_false
    end
  end

  it "reports when the program has exited" do
    Termisu::Testing.terminal("/bin/sh", ["-c", "printf done"], cols: 10, rows: 2) do |term|
      term.get_by_text("done").should be_true
      # Poll via the harness rather than a fixed sleep (robust on slow CI).
      term.wait_until(2.seconds) { term.exited? }.should be_true
    end
  end
end
