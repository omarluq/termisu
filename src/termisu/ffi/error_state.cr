require "crystal/thread_local_value"

module Termisu::FFI::ErrorState
  @@last_error = Crystal::ThreadLocalValue(String).new

  def self.current : String
    @@last_error.get { "" }
  end

  def self.set(message : String) : Nil
    @@last_error.set(message)
  end

  def self.clear : Nil
    @@last_error.set("")
  end

  def self.format(ex : Exception) : String
    msg = ex.message
    msg ? "#{ex.class.name}: #{msg}" : ex.class.name
  end
end
