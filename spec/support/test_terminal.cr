# Test-only Terminal subclass that captures all writes for verification.
#
# Useful for testing Terminal output including escape sequences
# like BSU/ESU for synchronized updates.
#
# Example:
# ```
# terminal = TestTerminal.new(sync_updates: true)
# terminal.set_cell(0, 0, 'X')
# terminal.render
# terminal.output.should contain(Termisu::Terminal::BSU)
# ```
class TestTerminal < Termisu::Terminal
  property writes : Array(String) = [] of String
  property captured_flush_count : Int32 = 0

  def initialize(*, sync_updates : Bool = true)
    super(sync_updates: sync_updates)
  end

  def write(data : String)
    @writes << data
    # Don't call super - we don't want to write to real TTY
  end

  def flush
    @captured_flush_count += 1
    # Don't call super - we don't want to flush real TTY
  end

  def output : String
    @writes.join
  end

  def clear_captured
    @writes.clear
    @captured_flush_count = 0
  end
end
