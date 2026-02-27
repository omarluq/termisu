class Termisu::FFI::Context
  getter termisu : ::Termisu

  @closed : Bool = false

  def initialize(sync_updates : Bool)
    @termisu = ::Termisu.new(sync_updates: sync_updates)
  end

  def close : Nil
    return if @closed
    @termisu.close
    @closed = true
  end
end
