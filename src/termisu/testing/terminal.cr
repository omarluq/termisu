module Termisu::Testing
  # High-level E2E harness: spawns a program on a PTY, continuously emulates its
  # output into a `Screen`, and exposes assertion helpers that mirror JS terminal
  # test runners (`get_by_text`, `get_cursor`, snapshot) — with auto-retrying
  # waits so tests don't sprinkle fixed `sleep`s.
  #
  # Prefer the block form which guarantees cleanup:
  #
  # ```
  # Termisu::Testing.terminal("./bin/app", cols: 100, rows: 50) do |t|
  #   t.get_by_text("Ready").should be_true
  #   t.write("q")
  # end
  # ```
  class Terminal
    # Byte sequences for common special keys (xterm/standard).
    KEYS = {
      up: "\e[A", down: "\e[B", right: "\e[C", left: "\e[D",
      enter: "\r", esc: "\e", tab: "\t", backspace: "\u{7f}", space: " ",
      home: "\e[H", end: "\e[F", page_up: "\e[5~", page_down: "\e[6~",
    }

    getter screen : Screen
    getter cols : Int32
    getter rows : Int32
    getter? exited : Bool = false

    @pty : Pty
    @started : Bool = false
    @last_activity : MonotonicTime

    def initialize(
      program : String,
      args : Array(String) = [] of String,
      *,
      @cols : Int32 = 100,
      @rows : Int32 = 50,
      env : Hash(String, String)? = nil,
    )
      @screen = Screen.new(@cols, @rows)
      @pty = Pty.new(program, args, cols: @cols, rows: @rows, env: env)
      @last_activity = monotonic_now
      start_reader
    end

    # Spawns *program*, yields the harness, and always cleans up.
    def self.terminal(
      program : String,
      args : Array(String) = [] of String,
      *,
      cols : Int32 = 100,
      rows : Int32 = 50,
      env : Hash(String, String)? = nil,
      &
    )
      merged = {"TERM" => "xterm-256color"}
      env.try { |e| merged.merge!(e) }
      term = new(program, args, cols: cols, rows: rows, env: merged)
      begin
        yield term
      ensure
        term.close
      end
    end

    # --- input ---

    # Sends raw text to the program.
    def write(data : String) : Nil
      @pty.write(data)
    end

    # Sends a single character.
    def key_press(char : Char) : Nil
      write(char.to_s)
    end

    # Sends a named special key (see `KEYS`).
    def key(name : Symbol) : Nil
      seq = KEYS[name]? || raise ArgumentError.new("unknown key #{name.inspect}")
      write(seq)
    end

    # Resizes the terminal (delivers SIGWINCH to the child).
    def resize(cols : Int32, rows : Int32) : Nil
      @cols = cols
      @rows = rows
      @pty.resize(cols, rows)
    end

    # --- assertions / readout ---

    # Waits (up to *timeout*) until *pattern* appears on screen. Returns whether
    # it became visible — assert with `.should be_true`.
    def get_by_text(pattern : String | Regex, timeout : Time::Span = 3.seconds) : Bool
      wait_until(timeout) { @screen.includes?(pattern) }
    end

    # Cursor position once the screen settles.
    def cursor : {Int32, Int32}
      wait_stable
      {@screen.cursor_x, @screen.cursor_y}
    end

    # Waits for *pattern* to appear, then returns its first {x, y} (or nil).
    def locate(pattern : String | Regex, timeout : Time::Span = 3.seconds) : {Int32, Int32}?
      get_by_text(pattern, timeout)
      @screen.locate(pattern)
    end

    # The text of screen row *y* once the screen settles.
    def row(y : Int32) : String
      wait_stable
      @screen.row_text(y)
    end

    # Sends a Ctrl+<char> combination (e.g. `ctrl('c')` → 0x03).
    def ctrl(char : Char) : Nil
      write(((char.downcase.ord) & 0x1f).chr.to_s)
    end

    # Whether the cursor is currently visible (waits for the screen to settle).
    def cursor_visible? : Bool
      wait_stable
      @screen.cursor_visible?
    end

    # Styled snapshot of the rendered screen (glyph grid + per-cell fg/bg/attr).
    # *mask* blanks volatile regions (matched per row) so animated screens are
    # deterministic.
    def snapshot(mask : Array(Regex) = [] of Regex) : String
      wait_stable
      @screen.to_styled_s(mask)
    end

    # Blocks until *block* returns true, or *timeout* elapses. Yields to the
    # reader fiber between checks (no busy spin).
    def wait_until(timeout : Time::Span = 3.seconds, &) : Bool
      deadline = monotonic_now + timeout
      loop do
        return true if yield
        return false if monotonic_now >= deadline
        sleep 5.milliseconds
      end
    end

    # Blocks until the program has produced no new output for *quiet_for*
    # (render-stable), or *timeout* elapses.
    def wait_stable(quiet_for : Time::Span = 80.milliseconds, timeout : Time::Span = 3.seconds) : Nil
      deadline = monotonic_now + timeout
      loop do
        break if @started && (monotonic_now - @last_activity) >= quiet_for
        break if monotonic_now >= deadline
        sleep 10.milliseconds
      end
    end

    # Stops the program and releases the PTY. Idempotent.
    def close : Nil
      @pty.close
    end

    private def start_reader : Nil
      spawn do
        buf = Bytes.new(8192)
        begin
          loop do
            n = @pty.master.read(buf)
            break if n == 0 # EOF
            @screen.feed(buf[0, n])
            @started = true
            @last_activity = monotonic_now
          end
        rescue IO::Error
          # master hung up (child exited; Linux raises EIO) — treat as EOF
        end
        @exited = true
      end
    end
  end

  # Convenience module-level entry: `Termisu::Testing.terminal(...) { |t| ... }`.
  def self.terminal(
    program : String,
    args : Array(String) = [] of String,
    *,
    cols : Int32 = 100,
    rows : Int32 = 50,
    env : Hash(String, String)? = nil,
    &
  )
    Terminal.terminal(program, args, cols: cols, rows: rows, env: env) do |term|
      yield term
    end
  end
end
