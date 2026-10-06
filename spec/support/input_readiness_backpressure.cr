# Fault fixtures use only lease-owned pipes, never the borrowed input descriptor.
class Termisu::Event::Source::Input
  private class ReadinessLease
    @control_blocked_for_spec = Atomic(Bool).new(false)
    @wake_blocked_for_spec = Atomic(Bool).new(false)

    private def record_control_backpressure_for_spec : Nil
      @control_blocked_for_spec.set(true)
    end

    private def record_wake_backpressure_for_spec : Nil
      @wake_blocked_for_spec.set(true)
    end

    def control_retry_for_spec : Bool
      reset_worker_for_spec
      control = @control_reader || raise "Missing control reader"
      flags = LibC.fcntl(control.fd, LibC::F_GETFL, 0)
      if flags == -1 || LibC.fcntl(control.fd, LibC::F_SETFL, flags | LibC::O_NONBLOCK) == -1
        raise IO::Error.from_errno("Could not configure nonblocking control fixture")
      end
      result = Atomic(Bool).new(false)
      @thread = Thread.new { result.set(read_command(control.fd).rearm?) }
      wait_for_backpressure_for_spec { @control_blocked_for_spec.get }
      rearm
      @thread.try(&.join)
      @thread = nil
      result.get
    end

    def saturated_cancel_for_spec : Bool
      reset_worker_for_spec
      control = @control_reader || raise "Missing control reader"
      writer = @control_writer || raise "Missing control writer"
      fill_pipe_for_spec(writer.fd)
      cancel
      result = Atomic(Bool).new(false)
      @thread = Thread.new { result.set(wait_for_command(control.fd).stop?) }
      @thread.try(&.join)
      @thread = nil
      result.get
    end

    def saturate_wake_for_spec : Nil
      writer = @wake_writer || raise "Missing wake writer"
      fill_pipe_for_spec(writer.fd)
    end

    def await_wake_backpressure_for_spec : Nil
      wait_for_backpressure_for_spec { @wake_blocked_for_spec.get }
    end

    private def reset_worker_for_spec : Nil
      cancel
      @thread.try(&.join)
      @thread = nil
      control = @control_reader || raise "Missing control reader"
      # Atomic cancellation can leave the original Stop byte unread. This is a
      # test-only worker reset; production restarts always allocate a new lease.
      byte = uninitialized UInt8
      loop do
        result = LibC.read(control.fd, pointerof(byte), 1)
        next if result == 1
        errno = Errno.value
        next if result < 0 && errno.eintr?
        break if result == 0 || errno.eagain?
        raise Termisu::IOError.new(errno, "Could not reset control fixture")
      end
      @cancelled.set(false)
    end

    private def fill_pipe_for_spec(fd : Int32) : Nil
      flags = LibC.fcntl(fd, LibC::F_GETFL, 0)
      if flags == -1 || LibC.fcntl(fd, LibC::F_SETFL, flags | LibC::O_NONBLOCK) == -1
        raise IO::Error.from_errno("Could not configure fixture pipe")
      end
      bytes = Bytes.new(4096, 1_u8) # Rearm/Ready both encode as 1.
      loop do
        result = LibC.write(fd, bytes.to_unsafe, bytes.size)
        next if result > 0
        errno = Errno.value
        return if errno.eagain?
        next if errno.eintr?
        raise Termisu::IOError.new(errno, "Could not saturate fixture pipe")
      end
    end

    private def wait_for_backpressure_for_spec(&ready : -> Bool) : Nil
      deadline = monotonic_now + 1.second
      until ready.call
        raise "Timed out waiting for native pipe backpressure" if monotonic_now >= deadline
        # Keep the source fiber paused until the native worker reaches EAGAIN.
        Thread.sleep(100.microseconds)
      end
    end
  end

  def self.control_retry_for_spec(fd : Int32) : Bool
    lease = ReadinessLease.new(fd)
    lease.control_retry_for_spec
  ensure
    lease.try(&.close)
  end

  def self.saturated_cancel_for_spec(fd : Int32) : Bool
    lease = ReadinessLease.new(fd)
    lease.saturated_cancel_for_spec
  ensure
    lease.try(&.close)
  end

  def saturate_readiness_wake_for_spec : Nil
    lease = @lease || raise "Missing readiness lease"
    lease.saturate_wake_for_spec
  end

  def await_readiness_backpressure_for_spec : Nil
    lease = @lease || raise "Missing readiness lease"
    lease.await_wake_backpressure_for_spec
  end
end
