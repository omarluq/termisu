require "spec"
require "../../../src/termisu"
require "../../../src/termisu/testing/pty"

# Smoke test for the PTY layer: spawn a real Termisu example through a controlling
# PTY and confirm we capture its rendered output. Requires `bin/simple` to exist
# (built by the e2e flow).
describe Termisu::Testing::Pty do
  it "spawns a program on a controlling PTY and captures its output" do
    pending! "bin/simple not built" unless File.exists?("bin/simple")

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
