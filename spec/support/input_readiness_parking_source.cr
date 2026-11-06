class InputReadinessParkingSource < Termisu::Event::Source::Input
  getter parked : Channel(Nil) = Channel(Nil).new(1)

  private def rearm_after_drain(lease : ReadinessLease, stop_signal : Channel(Nil),
                                descriptor_closed : Bool) : Nil
    super
    @parked.send(nil) if descriptor_closed
  end
end
