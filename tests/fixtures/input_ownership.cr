require "../../src/termisu"

private def show(termisu : Termisu, message : String, row : Int32) : Nil
  message.each_char_with_index do |char, column|
    termisu.set_cell(column, row, char)
  end
  termisu.render
end

private def same_fiber_close_rejected?(termisu : Termisu) : Bool
  termisu.close
  false
rescue Termisu::Error
  !termisu.@closed.get && termisu.current_mode == Termisu::Terminal::Mode.cooked
end

private def wait_for_key(
  termisu : Termisu,
  expected : Termisu::Input::Key,
  timeout : Time::Span = 2.seconds,
) : Bool
  deadline = monotonic_now + timeout
  while (remaining = deadline - monotonic_now) > Time::Span.zero
    event = termisu.poll_event(remaining)
    return false unless event
    return true if event.as?(Termisu::Event::Key).try(&.key) == expected
  end
  false
end

termisu = Termisu.new(sync_updates: false)

begin
  begin
    termisu.read_byte
  rescue Termisu::InputOwnershipError
    show(termisu, "LEASE REQUIRED", 0)
  end

  cooked_states = [] of Bool
  termisu.with_cooked_mode(preserve_screen: true) do
    cooked_states << !termisu.@input_source.running?
    termisu.with_raw_input do
      cooked_states << !termisu.@input_source.running?
    end
    cooked_states << !termisu.@input_source.running?
  end
  cooked_states << termisu.@input_source.running?
  cooked_nested = cooked_states.all?
  show(termisu, "COOKED RAW #{cooked_nested ? "OK" : "BAD"}", 1)

  raw_nested = false
  termisu.with_raw_input do
    outer_stopped = !termisu.@input_source.running?
    termisu.with_cooked_mode(preserve_screen: true) do
      raw_nested = outer_stopped && !termisu.@input_source.running?
    end
    raw_nested &&= !termisu.@input_source.running?
  end
  raw_nested &&= termisu.@input_source.running?
  show(termisu, "RAW COOKED #{raw_nested ? "OK" : "BAD"}", 2)

  first_entered = Channel(Nil).new
  release_first = Channel(Nil).new
  first_done = Channel(Exception?).new(1)
  second_started = Channel(Nil).new
  second_entered = Channel(Nil).new(1)
  release_second = Channel(Nil).new
  second_done = Channel(Exception?).new(1)

  spawn do
    error = nil.as(Exception?)
    begin
      termisu.with_cooked_mode(preserve_screen: true) do
        first_entered.send(nil)
        release_first.receive
      end
    rescue ex
      error = ex
    ensure
      first_done.send(error)
    end
  end
  first_entered.receive

  spawn do
    error = nil.as(Exception?)
    begin
      second_started.send(nil)
      termisu.with_password_mode(preserve_screen: true) do
        second_entered.send(nil)
        release_second.receive
      end
    rescue ex
      error = ex
    ensure
      second_done.send(error)
    end
  end
  second_started.receive
  Fiber.yield

  crossed = termisu.current_mode == Termisu::Terminal::Mode.cooked
  select
  when second_entered.receive
    crossed = false
  else
  end
  release_first.send(nil)
  crossed &&= first_done.receive.nil?
  second_entered.receive
  crossed &&= termisu.current_mode == Termisu::Terminal::Mode.password
  release_second.send(nil)
  crossed &&= second_done.receive.nil?
  crossed &&= termisu.current_mode == Termisu::Terminal::Mode.raw
  show(termisu, "CROSSED MODES #{crossed ? "OK" : "BAD"}", 3)

  same_fiber_close = false
  termisu.with_cooked_mode(preserve_screen: true) do
    same_fiber_close = same_fiber_close_rejected?(termisu)
  end
  same_fiber_close &&= termisu.current_mode == Termisu::Terminal::Mode.raw
  show(termisu, "SCOPE CLOSE #{same_fiber_close ? "OK" : "BAD"}", 4)

  show(termisu, "PROBE READY", 5)
  if wait_for_key(termisu, Termisu::Input::Key::PasteStart)
    show(termisu, "PROBE ESC", 6)
    sleep 100.milliseconds

    begin
      termisu.with_raw_input { }
    rescue Termisu::InputOwnershipError
      show(termisu, "PROBE RETAINED", 7)
    end

    # Complete the event-owned probe under explicit source quiescence. The
    # source normally polls non-blockingly; this bounded poll makes the PTY
    # fixture deterministic without changing parser deadline behavior.
    termisu.@input_source.stop
    retained = termisu.@input_parser.poll_event(2_000)
    termisu.@input_source.start(termisu.@event_loop.output)
    if retained.as?(Termisu::Event::Key).try(&.key) == Termisu::Input::Key::PasteEnd
      show(termisu, "PROBE COMPLETE", 8)
    end
  end

  termisu.with_raw_input do
    show(termisu, "RAW READY", 9)
    if termisu.wait_for_input(2_000)
      if bytes = termisu.read_bytes(3)
        show(termisu, "RAW #{bytes.hexstring}", 10)
      end
    end
  end

  show(termisu, "EVENT READY", 11)
  if event = termisu.poll_event(2.seconds)
    if key = event.as?(Termisu::Event::Key)
      show(termisu, "EVENT #{key.char}", 12)
    end
  end
  sleep 100.milliseconds
ensure
  termisu.close
end
