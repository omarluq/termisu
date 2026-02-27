module Termisu::FFI::ErrorState
  @@last_error = ""
  @@lock = Mutex.new

  def self.current : String
    @@lock.synchronize { @@last_error }
  end

  def self.set(message : String) : Nil
    @@lock.synchronize { @@last_error = message }
  end

  def self.clear : Nil
    set("")
  end

  def self.format(ex : Exception) : String
    msg = ex.message
    msg ? "#{ex.class.name}: #{msg}" : ex.class.name
  end
end
