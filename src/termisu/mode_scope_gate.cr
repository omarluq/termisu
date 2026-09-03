# Fiber-reentrant ownership gate for terminal mode scopes.
#
# The owner and recursion depth here are the only mode-scope ownership state.
# The ordinary mutex only protects that state; waiters park cooperatively on
# channels instead of blocking a scheduler thread.
class Termisu::ModeScopeGate
  @state_lock = Mutex.new
  @owner : Fiber? = nil
  @depth : Int32 = 0
  @waiters = Deque({Fiber, Channel(Nil)}).new

  def synchronize(&)
    acquire
    begin
      yield
    ensure
      release
    end
  end

  def owned_by_current_fiber? : Bool
    @state_lock.synchronize do
      @owner.try(&.same?(Fiber.current)) || false
    end
  end

  private def acquire : Nil
    fiber = Fiber.current
    ready = nil.as(Channel(Nil)?)

    @state_lock.synchronize do
      if @owner.try(&.same?(fiber))
        @depth += 1
      elsif @owner.nil?
        @owner = fiber
        @depth = 1
      else
        channel = Channel(Nil).new(1)
        ready = channel
        @waiters << {fiber, channel}
      end
    end

    ready.try(&.receive)
  end

  private def release : Nil
    ready = nil.as(Channel(Nil)?)

    @state_lock.synchronize do
      unless @owner.try(&.same?(Fiber.current))
        raise Termisu::Error.new("mode scope gate released by a fiber that does not own it")
      end

      @depth -= 1
      return unless @depth == 0

      if waiter = @waiters.shift?
        @owner = waiter[0]
        @depth = 1
        ready = waiter[1]
      else
        @owner = nil
      end
    end

    ready.try(&.send(nil))
  end
end
