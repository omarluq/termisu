class InputReadinessCountingReader < Termisu::Reader
  getter wait_count : Atomic(Int32) = Atomic(Int32).new(0)

  def wait_for_data(timeout_ms : Int32) : Bool
    @wait_count.add(1)
    super
  end
end
