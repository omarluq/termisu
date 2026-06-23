require "digest/md5"

module Termisu::Testing
  # Allocates a pseudo-terminal and spawns a program attached to it, exposing
  # the master side as an ordinary `IO::FileDescriptor` (read it for the child's
  # output; write to it to deliver input).
  #
  # SAFETY: spawning goes through Crystal's `Process` (a fork+exec the runtime is
  # built for, child reaped via `Process#wait`). We never call a raw
  # `fork`/`forkpty` — unsafe inside a GC'd, fibered runtime. The child adopts
  # the PTY slave as its **controlling terminal** via the `ctty-exec` shim (see
  # `ctty_exec.cr`), so a Termisu app's `open("/dev/tty")` resolves to our PTY.
  class Pty
    # `openpty(3)` lives in libutil on Linux/*BSD, libSystem on macOS (no -lutil).
    {% unless flag?(:darwin) %}@[Link("util")]{% end %}
    lib LibPty
      # int openpty(int *amaster, int *aslave, char *name,
      #             const struct termios *termp, const struct winsize *winp);
      fun openpty(amaster : LibC::Int*, aslave : LibC::Int*, name : LibC::Char*,
                  termp : Void*, winp : Void*) : LibC::Int
    end

    # The master side of the PTY. A PTY master is a character device, which
    # Crystal treats as non-blocking, so fiber reads yield through the event loop.
    getter master : IO::FileDescriptor

    # The spawned child. Signalling/reaping always target exactly this process.
    getter process : Process

    getter? closed = false
    @exit_code : Int32? = nil
    @reaped = false

    # Spawns *command* (with *args*) on a fresh PTY sized *cols* x *rows*.
    def initialize(
      command : String,
      args : Array(String) = [] of String,
      *,
      cols : Int32 = 80,
      rows : Int32 = 24,
      env : Process::Env = nil,
    )
      master_fd = uninitialized LibC::Int
      slave_fd = uninitialized LibC::Int

      ws = LibC::Winsize.new
      ws.ws_row = rows.to_u16
      ws.ws_col = cols.to_u16

      if LibPty.openpty(pointerof(master_fd), pointerof(slave_fd),
           Pointer(LibC::Char).null, Pointer(Void).null, pointerof(ws).as(Void*)) != 0
        raise IO::Error.from_errno("openpty failed")
      end

      @master = IO::FileDescriptor.new(master_fd)
      slave = IO::FileDescriptor.new(slave_fd)

      # Launch through the controlling-terminal shim with the slave as the
      # child's stdin/stdout/stderr. If spawning fails, close both PTY fds so
      # they don't leak, then re-raise.
      @process = begin
        Process.new(
          self.class.ctty_exec_path,
          [command] + args,
          input: slave,
          output: slave,
          error: slave,
          env: env,
        )
      rescue ex
        @master.close rescue nil
        slave.close rescue nil
        raise ex
      end

      # The child holds its own dup'd copies; close the parent's slave so the
      # master reports EOF once the child exits.
      slave.close
    end

    # Writes input bytes to the child, flushing immediately (keystrokes must not
    # sit buffered).
    def write(data : String | Bytes) : Nil
      return if @closed
      @master.write(data.is_a?(String) ? data.to_slice : data)
      @master.flush
    end

    # Tells the kernel (and child) about new terminal geometry via `TIOCSWINSZ`.
    def resize(cols : Int32, rows : Int32) : Nil
      return if @closed
      ws = LibC::Winsize.new
      ws.ws_row = rows.to_u16
      ws.ws_col = cols.to_u16
      LibC.ioctl(@master.fd, LibC::TIOCSWINSZ, pointerof(ws))
    end

    # Waits for the child to exit and returns its exit code (nil if signalled).
    # Cached; intended to be called after the master reports EOF.
    def reap : Int32?
      return @exit_code if @reaped
      @reaped = true
      @exit_code = (@process.wait.exit_code rescue nil)
    end

    # Hangs up the child and releases the master fd. Idempotent.
    def close : Nil
      return if @closed
      @closed = true
      begin
        @process.signal(Signal::HUP) unless @process.terminated?
      rescue
        # already gone / not signalable
      end
      @master.close rescue nil
      reap
    end

    # Path to the compiled `ctty-exec` shim. Honors `TERMISU_CTTY_EXEC`; otherwise
    # lazily compiles the embedded shim source to a cached temp binary (the test
    # environment always has `crystal` available). Memoized per process.
    @@ctty_exec_path : String?

    # Embedded shim source, so we don't depend on the .cr file existing at runtime.
    CTTY_EXEC_SRC = {{ read_file("#{__DIR__}/ctty_exec.cr") }}

    def self.ctty_exec_path : String
      @@ctty_exec_path ||= resolve_ctty_exec_path
    end

    private def self.resolve_ctty_exec_path : String
      if explicit = ENV["TERMISU_CTTY_EXEC"]?
        return explicit
      end

      # Key the cached binary on a hash of the shim source, so a changed shim
      # (e.g. after a shard upgrade) rebuilds instead of reusing a stale binary.
      digest = Digest::MD5.hexdigest(CTTY_EXEC_SRC)[0, 12]
      target = File.join(Dir.tempdir, "termisu-ctty-exec-#{digest}")
      return target if File.exists?(target)

      src = "#{target}.cr" # digest-keyed too, so concurrent builds don't clobber a shared source
      File.write(src, CTTY_EXEC_SRC)
      status = Process.run("crystal", ["build", src, "-o", target],
        output: Process::Redirect::Inherit, error: Process::Redirect::Inherit)
      unless status.success? && File.exists?(target)
        raise "Termisu::Testing: failed to build ctty-exec shim (set TERMISU_CTTY_EXEC to a prebuilt binary)"
      end
      target
    end
  end
end

# `TIOCSWINSZ` (set window size) — `backend.cr` already defines `TIOCGWINSZ`,
# `Winsize`, and the variadic `ioctl`; mirror its per-OS guard here.
lib LibC
  {% unless LibC.has_constant?(:TIOCSWINSZ) %}
    {% if flag?(:linux) %}
      TIOCSWINSZ = 0x5414
    {% elsif flag?(:darwin) %}
      TIOCSWINSZ = 0x80087467
    {% elsif flag?(:freebsd) || flag?(:openbsd) %}
      TIOCSWINSZ = 0x80087467
    {% else %}
      TIOCSWINSZ = 0x5414
    {% end %}
  {% end %}
end
