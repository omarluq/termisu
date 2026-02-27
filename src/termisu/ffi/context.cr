class Termisu::FFI::Context
  getter termisu : ::Termisu

  @closed : Atomic(Bool)

  def initialize(sync_updates : Bool)
    @closed = Atomic(Bool).new(false)
    @termisu = ::Termisu.new(sync_updates: sync_updates)
  end

  def close : Nil
    return unless @closed.compare_and_set(false, true)
    @termisu.close
  end
end
