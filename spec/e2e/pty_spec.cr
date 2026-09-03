require "./e2e_helper"

# Integration smoke test for the PTY layer: spawn a real Termisu example through
# a controlling PTY and confirm we capture its rendered output. Lives under
# spec/e2e (not the unit suite) because it needs a built example binary.
describe Termisu::Testing::Pty do
  it "hands facade input from raw reads back to event parsing without loss" do
    requires_binary "bin/input-ownership-fixture"

    Termisu::Testing.terminal(
      "bin/input-ownership-fixture",
      cols: 80,
      rows: 13,
      env: {"TERM" => "xterm-256color"},
    ) do |term|
      term.get_by_text("LEASE REQUIRED").should be_true
      term.get_by_text("COOKED RAW OK").should be_true
      term.get_by_text("RAW COOKED OK").should be_true
      term.get_by_text("CROSSED MODES OK").should be_true
      term.get_by_text("SCOPE CLOSE OK").should be_true
      term.get_by_text("PROBE READY").should be_true

      term.write("\e[200~")
      term.get_by_text("PROBE ESC").should be_true
      term.write("\e")
      term.get_by_text("PROBE RETAINED").should be_true
      term.write("[201~")
      term.get_by_text("PROBE COMPLETE").should be_true
      term.get_by_text("RAW READY").should be_true

      term.write("\e[A")
      term.get_by_text("RAW 1b5b41").should be_true
      term.get_by_text("EVENT READY").should be_true

      term.write("z")
      term.get_by_text("EVENT z").should be_true
      term.row(11).rstrip.should eq("EVENT READY")
      term.row(12).rstrip.should eq("EVENT z")
    end
  end

  it "spawns a program on a controlling PTY and captures its output" do
    requires_binary "bin/simple"

    pty = Termisu::Testing::Pty.new("bin/simple", cols: 100, rows: 50,
      env: {"TERM" => "xterm-256color"})

    captured = IO::Memory.new
    pty.master.read_timeout = 400.milliseconds
    buf = Bytes.new(4096)
    deadline = monotonic_now + 3.seconds

    begin
      while monotonic_now < deadline
        n = pty.master.read(buf)
        break if n == 0
        captured.write(buf[0, n])
        break if captured.to_s.includes?("Strikethrough")
      end
    rescue IO::TimeoutError
      # no more output within the window
    rescue IO::Error
      # master hung up (child exited / EIO on Linux) — treat as EOF
    ensure
      pty.close
    end

    captured.to_s.should contain("Strikethrough")
  end
end
