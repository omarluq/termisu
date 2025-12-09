# Pipe helpers for testing components that require file descriptors.
#
# Provides utilities for creating Unix pipes and LibC bindings
# needed for testing Reader, Parser, and Input sources.
module PipeHelpers
  # Creates a Unix pipe and returns the read/write file descriptors.
  #
  # Returns a tuple of {read_fd, write_fd}.
  # Caller is responsible for closing both file descriptors.
  #
  # Example:
  # ```
  # read_fd, write_fd = create_pipe
  # begin
  #   LibC.write(write_fd, bytes, bytes.size)
  #   # ... use read_fd ...
  # ensure
  #   LibC.close(read_fd)
  #   LibC.close(write_fd)
  # end
  # ```
  def create_pipe : {Int32, Int32}
    fds = uninitialized StaticArray(Int32, 2)
    result = LibC.pipe(fds)
    raise "pipe() failed" if result != 0
    {fds[0], fds[1]}
  end
end

# Ensure LibC has required functions for pipe operations.
lib LibC
  {% unless LibC.has_method?(:pipe) %}
    fun pipe(fds : Int32*) : Int32
  {% end %}

  {% unless LibC.has_method?(:write) %}
    fun write(fd : Int32, buf : UInt8*, count : LibC::SizeT) : LibC::SSizeT
  {% end %}

  {% unless LibC.has_method?(:fcntl) %}
    fun fcntl(fd : Int32, cmd : Int32, arg : Int32) : Int32
  {% end %}
end
