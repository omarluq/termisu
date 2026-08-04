# Availability probes for specs that need a real terminfo database.
#
# Crystal's spec DSL has no runtime skip: calling `pending` inside a running example
# raises "Can't nest `it` or `pending`". A spec that depends on terminfo therefore has
# to decide *when it is declared* whether to run, which is what these are for — call
# them at `describe` level to pick `it` or `pending`.
#
# Deciding up front is also what keeps assertions out of a rescue. The alternative
# shape, wrapping the body in `rescue -> pending`, cannot tell "no terminfo here" from
# "this assertion just failed", so it reports a broken expectation as a skipped system.
module TerminfoHelpers
  extend self

  # Whether the terminfo database *name* can be loaded on this system.
  def terminfo_db_available?(name : String) : Bool
    Termisu::Terminfo::Database.new(name).load
    true
  rescue
    false
  end

  # Whether *name*'s compiled entry uses the extended 32-bit number format
  # (magic 542) rather than the legacy 16-bit one (282). Which one a system ships
  # is a property of how its terminfo was compiled, so specs covering the extended
  # reader have to check rather than assume.
  def terminfo_db_extended?(name : String) : Bool
    data = Termisu::Terminfo::Database.new(name).load
    IO::Memory.new(data).read_bytes(Int16, IO::ByteFormat::LittleEndian) == 542
  rescue
    false
  end

  # Whether `Termisu::Terminfo.new` succeeds for the ambient TERM.
  def terminfo_available? : Bool
    Termisu::Terminfo.new
    true
  rescue
    false
  end
end
