# Controlling-terminal exec shim for Termisu::Testing.
#
# This is a STANDALONE PROGRAM, never `require`d (it has top-level code). It is
# compiled to a small binary (e.g. `bin/ctty-exec`) and used by
# `Termisu::Testing::Pty` to launch the program under test.
#
# Why it exists: a TUI built on Termisu opens `/dev/tty` — the *controlling
# terminal* of the process. For that to resolve to our PTY slave (rather than
# the spec runner's own terminal, or nothing in CI), the child must adopt the
# slave as its controlling terminal. There is no pre-exec hook on Crystal's
# `Process`, so we exec this shim with the slave wired to fd 0/1/2; it calls
# `login_tty(0)` (new session + `TIOCSCTTY` on the slave + dup to 0/1/2) and
# then `exec`s the real program — all on the safe Process path, no raw fork.
#
# `login_tty(3)` lives in libutil on Linux/*BSD and in libSystem on macOS, so
# the `@[Link("util")]` is gated off Darwin.
{% unless flag?(:darwin) %}@[Link("util")]{% end %}
lib LibCttyExec
  # int login_tty(int fd);
  fun login_tty(fd : Int32) : Int32
end

if ARGV.empty?
  STDERR.puts "ctty-exec: usage: ctty-exec <program> [args...]"
  exit 2
end

# fd 0 is the PTY slave (wired by the parent's Process.new). Make it our
# controlling terminal, then hand off to the real program.
if LibCttyExec.login_tty(0) != 0
  STDERR.puts "ctty-exec: login_tty failed: #{Errno.value}"
  exit 1
end

program = ARGV[0]
args = ARGV.size > 1 ? ARGV[1..] : [] of String

# Replaces this process image; inherits env (incl. TERM) from how we were spawned.
Process.exec(program, args)
