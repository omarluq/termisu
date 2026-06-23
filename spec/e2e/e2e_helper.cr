require "spec"
require "../../src/termisu/testing"

# Shared helpers for the Crystal-native E2E suite. These specs drive the compiled
# example binaries (bin/simple, bin/showcase, ...) through a real PTY using
# `Termisu::Testing`. Build the examples first (e.g. `bin/hace e2e`).
module E2EHelper
  SNAPSHOT_DIR = "spec/e2e/__snapshots__"

  # Skips the example with a clear message if its binary hasn't been built.
  macro requires_binary(path)
    pending!("{{path.id}} not built — run `bin/hace e2e`") unless File.exists?({{path}})
  end

  # Compares the terminal's rendered screen against a committed snapshot.
  # Set `UPDATE_SNAPSHOTS=1` to (re)generate. In normal mode a missing snapshot
  # fails (so an accidental deletion can't pass CI silently).
  #
  # *mask* replaces volatile regions (spinners, frame counters, FPS, a moving
  # ball, …) with same-width blanks so animated examples snapshot
  # deterministically while still capturing the static layout/chrome.
  def assert_snapshot(term : Termisu::Testing::Terminal, name : String, mask : Array(Regex) = [] of Regex) : Nil
    actual = term.snapshot(mask)
    path = File.join(SNAPSHOT_DIR, "#{name}.snap.txt")
    if ENV["UPDATE_SNAPSHOTS"]?
      Dir.mkdir_p(SNAPSHOT_DIR)
      File.write(path, actual)
      return
    end
    fail "Missing snapshot #{path} — run `UPDATE_SNAPSHOTS=1 bin/hace e2e:update`" unless File.exists?(path)
    actual.should eq(File.read(path))
  end
end

include E2EHelper
