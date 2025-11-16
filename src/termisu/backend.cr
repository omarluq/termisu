# Abstract backend interface for terminal rendering.
#
# Separates rendering logic from I/O operations, enabling
# different backend implementations (terminal, in-memory, etc.).
abstract class Termisu::Backend
  # Writes data to the backend.
  abstract def write(data : String)

  # Flushes any buffered output.
  abstract def flush

  # Returns the backend dimensions as {width, height}.
  abstract def size : {Int32, Int32}

  # Closes the backend and releases resources.
  abstract def close
end
