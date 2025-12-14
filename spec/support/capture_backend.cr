# Mock backend that captures all write() calls for testing.
#
# Useful for testing Terminal output including escape sequences
# like BSU/ESU for synchronized updates.
#
# Example:
# ```
# backend = CaptureBackend.new
# terminal = Termisu::Terminal.new(backend)
# terminal.render
# backend.writes.should contain(Termisu::Terminal::BSU)
# ```
class CaptureBackend
  property writes : Array(String) = [] of String
  property flush_count : Int32 = 0
  property mock_size : {Int32, Int32} = {80, 24}

  getter infd : Int32 = 0
  getter outfd : Int32 = 1

  def write(data : String)
    @writes << data
  end

  def flush
    @flush_count += 1
  end

  def size : {Int32, Int32}
    @mock_size
  end

  def enable_raw_mode
  end

  def disable_raw_mode
  end

  def raw_mode? : Bool
    false
  end

  def with_raw_mode(&)
    yield
  end

  # ameba:disable Naming/AccessorMethodName
  def set_mode(mode : Termisu::Terminal::Mode)
  end

  def current_mode : Termisu::Terminal::Mode?
    nil
  end

  def with_mode(mode : Termisu::Terminal::Mode, &)
    yield
  end

  def close
  end

  # Returns all writes joined together.
  def output : String
    @writes.join
  end

  # Checks if a specific sequence was written.
  def wrote?(sequence : String) : Bool
    @writes.includes?(sequence)
  end

  # Clears all captured data.
  def clear
    @writes.clear
    @flush_count = 0
  end
end
