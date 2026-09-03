# Terminal input event source.
#
# Wraps `Reader` and `Input::Parser` to produce Key and Mouse events
# via a dedicated fiber.
#
# ## Usage
#
# ```
# reader = Termisu::Reader.new(terminal.infd)
# parser = Termisu::Input::Parser.new(reader)
# input = Termisu::Event::Source::Input.new(reader, parser)
#
# loop = Termisu::Event::Loop.new
# loop.add_source(input)
# loop.start
#
# while event = loop.output.receive?
#   case event
#   when Termisu::Event::Key
#     break if event.key.escape?
#   when Termisu::Event::Mouse
#     puts "Click at #{event.x},#{event.y}"
#   end
# end
# ```
#
# ## Thread Safety
#
# Uses `Atomic(Bool)` for the running state. Safe to call `start`/`stop`
# from different fibers.
class Termisu::Event::Source::Input < Termisu::Event::Source
  Log = Termisu::Logs::Event

  # Retained for source compatibility. Input readiness is no longer polled on
  # this interval.
  IDLE_SLEEP = 4.milliseconds

  # Maximum events drained per loop iteration.
  #
  # Prevents a continuous input stream from monopolizing the scheduler
  # while still allowing bursty input to be processed quickly.
  MAX_DRAIN_PER_CYCLE = 64

  # A run-local bridge between blocking poll(2) and Crystal's cooperative IO.
  #
  # The duplicated input descriptor is used only for readiness: Parser remains
  # the sole consumer. It is never wrapped in
  # IO::FileDescriptor because that constructor may set O_NONBLOCK on the shared
  # open-file description.
  # A control pipe cancels or rearms the poll worker, while a second pipe wakes
  # the source fiber through Crystal's ordinary public IO API.
  private class ReadinessLease
    # POSIX specifies F_DUPFD as command zero on all supported targets.
    private F_DUPFD = 0

    enum Status : UInt8
      Ready     = 1
      Hangup    = 2
      Error     = 3
      Cancelled = 4
    end

    private enum Command : UInt8
      Rearm = 1
      Stop  = 2
    end

    @input_fd : Int32 = -1
    @wake_reader : IO::FileDescriptor?
    @wake_writer : IO::FileDescriptor?
    @control_reader : IO::FileDescriptor?
    @control_writer : IO::FileDescriptor?
    @thread : Thread?
    @cancelled = Atomic(Bool).new(false)
    @closed = Atomic(Bool).new(false)

    def initialize(fd : Int32)
      @input_fd = duplicate(fd)
      wake_reader, wake_writer = IO.pipe
      @wake_reader = wake_reader
      @wake_writer = wake_writer
      control_reader, control_writer = IO.pipe
      @control_reader = control_reader
      @control_writer = control_writer
      input_fd = @input_fd
      wake_fd = wake_writer.fd
      control_fd = control_reader.fd
      @thread = Thread.new do
        worker_loop(input_fd, wake_fd, control_fd)
      rescue error
        # Wake the source fiber so stop can reach the synchronous join, which
        # re-raises this original worker failure after closing all resources.
        publish(wake_fd, Status::Error)
        raise error
      end
    rescue error
      close_descriptors
      raise error
    end

    def wait(deadline : MonotonicTime?) : Status?
      reader = @wake_reader || raise IO::Error.new("Input readiness lease is closed")
      if deadline
        remaining = deadline - monotonic_now
        return if remaining <= Time::Span.zero
        reader.read_timeout = remaining
      else
        reader.read_timeout = nil
      end

      byte = reader.read_byte
      byte ? Status.from_value(byte) : nil
    rescue IO::TimeoutError
      nil
    end

    def rearm : Nil
      write_command(Command::Rearm)
    end

    def cancel : Nil
      return unless @cancelled.compare_and_set(false, true)[1]

      write_command(Command::Stop) rescue nil
    end

    def close : Nil
      return unless @closed.compare_and_set(false, true)[1]

      cancel
      begin
        @thread.try(&.join)
      ensure
        # Thread#join re-raises a worker failure. Descriptor ownership still
        # ends here, and the worker error remains the primary exception.
        close_descriptors
      end
    end

    {% if @top_level.has_constant?(:TERMISU_INPUT_READINESS_SPEC) %}
      def fail_worker_for_spec : Array(Int32)
        cancel
        @thread.try(&.join)
        @thread = Thread.new { raise ArgumentError.new("readiness worker fault") }
        descriptors = [
          @wake_reader.not_nil!.fd,
          @wake_writer.not_nil!.fd,
          @control_reader.not_nil!.fd,
          @control_writer.not_nil!.fd,
        ]
        descriptors << @input_fd
        descriptors
      end
    {% end %}

    private def close_descriptors : Nil
      @wake_reader.try(&.close) rescue nil
      @wake_writer.try(&.close) rescue nil
      @control_reader.try(&.close) rescue nil
      @control_writer.try(&.close) rescue nil
      LibC.close(@input_fd) if @input_fd >= 0
      @input_fd = -1
    end

    private def duplicate(fd : Int32) : Int32
      duplicate = LibC.fcntl(fd, F_DUPFD, 0)
      raise IO::Error.from_errno("Could not duplicate input descriptor") if duplicate == -1

      if LibC.fcntl(duplicate, LibC::F_SETFD, LibC::FD_CLOEXEC) == -1
        errno = Errno.value
        LibC.close(duplicate)
        Errno.value = errno
        raise IO::Error.from_errno("Could not configure input descriptor duplicate")
      end
      duplicate
    end

    private def worker_loop(input_fd : Int32, wake_fd : Int32, control_fd : Int32) : Nil
      loop do
        pollfds = uninitialized StaticArray(Termisu::System::Poll::Pollfd, 2)
        control_pollfd = uninitialized Termisu::System::Poll::Pollfd
        control_pollfd.fd = control_fd
        control_pollfd.events = Termisu::System::Poll::POLLIN
        control_pollfd.revents = 0_i16
        pollfds[0] = control_pollfd
        input_pollfd = uninitialized Termisu::System::Poll::Pollfd
        input_pollfd.fd = input_fd
        input_pollfd.events = Termisu::System::Poll::POLLIN
        input_pollfd.revents = 0_i16
        pollfds[1] = input_pollfd

        result = Termisu::System::Poll.poll(
          pollfds.to_unsafe,
          Termisu::System::Poll::NfdsT.new(2),
          -1
        )
        if result < 0
          next if Errno.value.eintr?
          publish(wake_fd, Status::Error)
          return
        end

        # Cancellation wins a simultaneous input/HUP wake. The worker publishes
        # it through the cooperative pipe; no cross-fiber descriptor close is
        # needed to interrupt the source fiber on kqueue-based platforms.
        if readable?(pollfds[0].revents)
          if read_command(control_fd).stop?
            publish(wake_fd, Status::Cancelled)
            return
          end
        end
        next unless pollfds[1].revents != 0

        status = classify(pollfds[1].revents)
        return unless publish(wake_fd, status)
        if wait_for_command(control_fd).stop?
          publish(wake_fd, Status::Cancelled)
          return
        end
      end
    end

    private def wait_for_command(control_fd : Int32) : Command
      loop do
        pollfd = uninitialized Termisu::System::Poll::Pollfd
        pollfd.fd = control_fd
        pollfd.events = Termisu::System::Poll::POLLIN
        pollfd.revents = 0_i16
        result = Termisu::System::Poll.poll(
          pointerof(pollfd),
          Termisu::System::Poll::NfdsT.new(1),
          -1
        )
        next if result < 0 && Errno.value.eintr?
        return Command::Stop if result <= 0
        return read_command(control_fd)
      end
    end

    private def read_command(fd : Int32) : Command
      byte = uninitialized UInt8
      loop do
        result = LibC.read(fd, pointerof(byte), 1)
        return Command.from_value(byte) if result == 1
        next if result < 0 && Errno.value.eintr?
        return Command::Stop
      end
    end

    private def write_command(command : Command) : Nil
      writer = @control_writer || raise IO::Error.new("Input readiness lease is closed")
      write_byte(writer.fd, command.value)
    end

    private def publish(fd : Int32, status : Status) : Bool
      write_byte(fd, status.value)
      true
    rescue IO::Error
      false
    end

    private def write_byte(fd : Int32, byte : UInt8) : Nil
      loop do
        result = LibC.write(fd, pointerof(byte), 1)
        return if result == 1
        next if result < 0 && Errno.value.eintr?
        raise IO::Error.from_errno("Input readiness pipe write failed")
      end
    end

    private def readable?(events : Int16) : Bool
      mask = Termisu::System::Poll::POLLIN |
             Termisu::System::Poll::POLLHUP |
             Termisu::System::Poll::POLLERR |
             Termisu::System::Poll::POLLNVAL
      (events & mask) != 0
    end

    private def classify(events : Int16) : Status
      if (events & Termisu::System::Poll::POLLNVAL) != 0
        Status::Error
      elsif (events & Termisu::System::Poll::POLLHUP) != 0
        # HUP can accompany POLLIN/POLLERR while trailing bytes remain.
        Status::Hangup
      elsif (events & Termisu::System::Poll::POLLERR) != 0
        Status::Error
      else
        Status::Ready
      end
    end
  end

  {% if @top_level.has_constant?(:TERMISU_INPUT_READINESS_SPEC) %}
    def self.worker_failure_cleanup_for_spec(fd : Int32) : {Array(Int32), Exception?}
      lease = ReadinessLease.new(fd)
      descriptors = lease.fail_worker_for_spec
      error = begin
        lease.close
        nil
      rescue ex
        ex
      end
      {descriptors, error}
    end
  {% end %}

  @reader : Termisu::Reader
  @parser : Termisu::Input::Parser
  @running : Atomic(Bool)
  @lifecycle_lock : Mutex
  @stop_signal : Channel(Nil)?
  @done : Channel(Nil)?
  @fiber : Fiber?
  @lease : ReadinessLease?
  @pending_event : Event::Any?

  # Creates a new input source.
  #
  # - `reader` - Reader instance for raw input
  # - `parser` - Parser instance for escape sequence parsing
  def initialize(@reader : Termisu::Reader, @parser : Termisu::Input::Parser)
    @running = Atomic(Bool).new(false)
    @lifecycle_lock = Mutex.new
  end

  # Starts waiting for input events and sending them to the output channel.
  #
  # Each run owns its descriptor duplicate, cancellation pipes, worker, and
  # source fiber. A previous run is synchronously joined before replacement.
  def start(output : Channel(Event::Any)) : Nil
    @lifecycle_lock.synchronize do
      return if @running.get
      cleanup_stopped_run

      lease = ReadinessLease.new(@reader.@fd)
      stop_signal = Channel(Nil).new
      done = Channel(Nil).new
      @lease = lease
      @stop_signal = stop_signal
      @done = done
      @running.set(true)

      @fiber = spawn(name: "termisu-input") do
        run_loop(output, stop_signal, lease)
      ensure
        @running.set(false)
        lease.cancel
        done.close
      end

      lifecycle_log { Log.debug { "Input source started" } }
    end
  end

  # Stops input processing and synchronously releases every run-owned resource.
  #
  # When this method returns, the parser no longer touches the reader, so
  # ownership can be handed to a raw-input caller without splitting a sequence.
  def stop : Nil
    @lifecycle_lock.synchronize do
      return unless @fiber || @lease

      @running.set(false)
      @stop_signal.try { |signal| signal.close unless signal.closed? }
      @lease.try(&.cancel)
      @done.try(&.receive?)
      cleanup_stopped_run
      lifecycle_log { Log.debug { "Input source stopped" } }
    end
  end

  # Prepares the stopped source to hand its reader to a raw-input consumer.
  #
  # Callers must stop the source first. A parsed event blocked on backpressure
  # and bytes retained by an in-progress parser probe both remain event-owned;
  # handing the reader to a raw consumer in either state would reorder or split
  # the input stream.
  def prepare_raw_handoff : Bool
    @lifecycle_lock.synchronize do
      !@running.get && @pending_event.nil? && @parser.prepare_raw_handoff
    end
  end

  # Returns true if the input source is currently running.
  def running? : Bool
    @running.get
  end

  # Returns the source name for identification.
  def name : String
    "input"
  end

  private def cleanup_stopped_run : Nil
    lease = @lease
    @lease = nil
    @fiber = nil
    @stop_signal = nil
    @done = nil
    lease.try(&.close)
  end

  private def run_loop(
    output : Channel(Event::Any),
    stop_signal : Channel(Nil),
    lease : ReadinessLease,
  ) : Nil
    # A complete event retained across backpressure has precedence over bytes
    # that arrived later, and does not require descriptor readiness.
    return unless drain_pending_event(output, stop_signal)

    drain_initial_buffer(output, stop_signal)
    readiness_loop(output, stop_signal, lease)
  rescue Channel::ClosedError
    # Channel closed during shutdown - exit gracefully.
    Log.debug { "Input channel closed, exiting" }
  rescue error : IO::Error
    raise error if @running.get
  end

  private def drain_initial_buffer(
    output : Channel(Event::Any),
    stop_signal : Channel(Nil),
  ) : Nil
    # A prior parser/raw-owner call may have filled Reader past the event it
    # consumed. Those bytes precede future descriptor readiness.
    while @running.get && parser_buffered_input?
      emitted, exhausted = drain_cycle(output, stop_signal)
      break unless exhausted && parser_buffered_input?
      Fiber.yield if emitted
    end
  end

  private def readiness_loop(
    output : Channel(Event::Any),
    stop_signal : Channel(Nil),
    lease : ReadinessLease,
  ) : Nil
    descriptor_closed = false
    while @running.get
      status = lease.wait(parser_deadline)
      break unless @running.get
      break if status == ReadinessLease::Status::Cancelled

      if status == ReadinessLease::Status::Error
        raise Termisu::IOError.select_failed(Errno::EBADF)
      end
      descriptor_closed ||= status == ReadinessLease::Status::Hangup

      begin
        emitted = drain_available(output, stop_signal, descriptor_closed)
        return unless @running.get
      rescue error : Termisu::IOError
        # Some PTYs report EIO rather than a zero-byte read after HUP. Trailing
        # bytes were drained first; remain cancellably parked like ordinary EOF.
        raise error unless descriptor_closed
        next
      end

      eof = @reader.@eof
      lease.rearm unless eof || descriptor_closed
      Fiber.yield if emitted
    end
  end

  private def drain_pending_event(
    output : Channel(Event::Any),
    stop_signal : Channel(Nil),
  ) : Bool
    return true unless event = @pending_event
    return false unless send_event(output, stop_signal, event)

    @pending_event = nil
    true
  end

  private def drain_available(
    output : Channel(Event::Any),
    stop_signal : Channel(Nil),
    descriptor_closed : Bool,
  ) : Bool
    emitted, exhausted = drain_cycle(output, stop_signal)

    # HUP can be reported while more than one Reader buffer of trailing input
    # remains. Keep consuming until read(2) reaches EOF (or a PTY reports EIO),
    # yielding between bounded cycles so a large tail stays scheduler-fair.
    while @running.get && ((exhausted && parser_buffered_input?) ||
          (descriptor_closed && !@reader.@eof))
      Fiber.yield
      cycle_emitted, exhausted = drain_cycle(output, stop_signal)
      emitted ||= cycle_emitted
      # A few PTY implementations can report HUP before a nonblocking read
      # returns EAGAIN. Do not turn that mismatch into a tight drain loop.
      break if descriptor_closed && !cycle_emitted && !parser_buffered_input?
    end

    emitted
  end

  private def drain_cycle(
    output : Channel(Event::Any),
    stop_signal : Channel(Nil),
  ) : {Bool, Bool}
    emitted = false
    drained = 0

    while @running.get && drained < MAX_DRAIN_PER_CYCLE
      event = @parser.poll_event(0)
      break unless event

      unless send_event(output, stop_signal, event)
        # The parser already consumed this complete event. Keep it for the next
        # run instead of losing it when a full output channel is paused.
        @pending_event = event
        return {emitted, false}
      end

      emitted = true
      drained += 1
    end

    {emitted, drained == MAX_DRAIN_PER_CYCLE}
  end

  # Parser and Reader are private implementation collaborators of this source.
  # Direct ivar access keeps readiness/deadline plumbing out of the public API.
  private def parser_deadline : MonotonicTime?
    @parser.@paste_deadline
  end

  private def parser_buffered_input? : Bool
    !@parser.@pending.empty? || @reader.@buffer_pos < @reader.@buffer_len
  end

  private def send_event(
    output : Channel(Event::Any),
    stop_signal : Channel(Nil),
    event : Event::Any,
  ) : Bool
    select
    when output.send(event)
      true
    when stop_signal.receive?
      false
    end
  end
end
