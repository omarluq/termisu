# Process-global ownership guard for the controlling terminal.
#
# A process has one controlling terminal and Termisu also installs a global
# SIGWINCH handler and logging backend. Letting two instances manage those
# resources independently makes either instance's shutdown corrupt the other.
class Termisu::TerminalOwnership
  @@owned = Atomic(Bool).new(false)

  @released = Atomic(Bool).new(false)

  private def initialize
  end

  def self.acquire : self
    acquired = @@owned.compare_and_set(false, true, :acquire, :relaxed)[1]
    unless acquired
      raise Termisu::TerminalInUseError.new(
        "The process terminal is already controlled by another live Termisu instance"
      )
    end

    new
  end

  # Releases this lease at most once. In particular, a repeated close on an old
  # instance cannot release the lease subsequently acquired by a new instance.
  def release : Nil
    return unless @released.compare_and_set(false, true, :acquire, :relaxed)[1]

    @@owned.set(false, :release)
  end
end
