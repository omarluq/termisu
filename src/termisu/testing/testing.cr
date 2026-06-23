# Termisu::Testing — a terminal E2E testing harness for Termisu apps.
#
# Opt-in: `require "termisu/testing"`. NOT loaded by `require "termisu"` (the core
# auto-load glob `require "./termisu/*"` is non-recursive and there is
# deliberately no top-level `src/termisu/testing.cr`), so the PTY/`libutil`
# binding only links when you ask for it.
#
# It drives a compiled program through a real PTY, emulates the program's output
# into a 2D cell grid, and lets you assert on what's on screen — mirroring the
# `getByText` / `getCursor` / snapshot API of JS terminal test runners, but pure
# Crystal with zero foreign toolchain (runs identically on Linux/macOS/FreeBSD).
#
# ```
# require "termisu/testing"
#
# Termisu::Testing.terminal("./bin/myapp", cols: 100, rows: 50) do |t|
#   t.get_by_text("Hello").should be_true
#   t.write("q")
# end
# ```
require "../../termisu"
require "./pty"
require "./screen"
require "./terminal"

module Termisu::Testing
end
