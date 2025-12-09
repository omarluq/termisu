# Central event loop multiplexer.
#
# Manages multiple `Event::Source` instances and provides a unified output
# channel for all events. Handles lifecycle management and graceful shutdown.
#
# ## Usage
#
# ```
# loop = Termisu::Event::Loop.new
#
# # Add event sources
# loop.add_source(input_source)
# loop.add_source(resize_source)
# loop.add_source(timer_source)
#
# # Start all sources
# loop.start
#
# # Receive events from unified channel
# while event = loop.output.receive?
#   case event
#   when Termisu::Event::Key
#     break if event.key.escape?
#   when Termisu::Event::Tick
#     # Handle animation frame
#   end
# end
#
# # Stop all sources and cleanup
# loop.stop
# ```
#
# ## Thread Safety
#
# The Event::Loop uses `Atomic(Bool)` for thread-safe state management.
# All public methods are safe to call from multiple fibers.
#
# ## Shutdown Behavior
#
# When `stop` is called:
# 1. Running state is set to false (atomic)
# 2. All sources are stopped
# 3. Brief wait for fibers to exit gracefully
# 4. Output channel is closed
#
# The shutdown timeout prevents hanging on misbehaving sources.
class Termisu::Event::Loop
  Log = Termisu::Logs::Event

  # Default event channel buffer size.
  # 32 events ~= 0.5 seconds of activity at 60 FPS.
  DEFAULT_BUFFER_SIZE = 32

  # Graceful shutdown timeout in milliseconds.
  # Sources have this long to finish before channel is closed.
  SHUTDOWN_TIMEOUT_MS = 100

  @sources : Array(Source)
  @output : Channel(Any)
  @running : Atomic(Bool)

  # Creates a new Event::Loop with the specified buffer size.
  #
  # The buffer size determines how many events can be queued before
  # send operations block. Larger buffers reduce blocking but use more memory.
  def initialize(buffer_size : Int32 = DEFAULT_BUFFER_SIZE)
    @sources = [] of Source
    @output = Channel(Any).new(buffer_size)
    @running = Atomic(Bool).new(false)
    Log.debug { "Event::Loop created with buffer_size=#{buffer_size}" }
  end

  # Adds an event source to the loop.
  #
  # If the loop is already running, the source is started immediately.
  # Otherwise, it will be started when `start` is called.
  #
  # Returns self for method chaining.
  def add_source(source : Source) : self
    @sources << source
    Log.debug { "Added source: #{source.name}" }

    if @running.get
      source.start(@output)
      Log.debug { "Auto-started source: #{source.name}" }
    end

    self
  end

  # Removes an event source from the loop.
  #
  # If the source is running, it is stopped before removal.
  # Removing a non-existent source is a no-op.
  #
  # Returns self for method chaining.
  def remove_source(source : Source) : self
    if @sources.includes?(source)
      if source.running?
        source.stop
        Log.debug { "Stopped source before removal: #{source.name}" }
      end
      @sources.delete(source)
      Log.debug { "Removed source: #{source.name}" }
    end

    self
  end

  # Starts the event loop and all registered sources.
  #
  # Each source begins producing events to the shared output channel.
  # This is a non-blocking operation - sources run in their own fibers.
  #
  # Returns self for method chaining.
  def start : self
    return self unless @running.compare_and_set(false, true)

    Log.info { "Starting Event::Loop with #{@sources.size} source(s)" }

    @sources.each do |source|
      source.start(@output)
      Log.debug { "Started source: #{source.name}" }
    end

    Log.debug { "All sources started: #{source_names}" }

    self
  end

  # Stops the event loop and all sources.
  #
  # Performs graceful shutdown:
  # 1. Sets running state to false
  # 2. Stops all sources
  # 3. Waits briefly for fibers to exit
  # 4. Closes the output channel
  #
  # This unblocks any receivers waiting on the channel.
  # Safe to call multiple times (idempotent).
  #
  # Returns self for method chaining.
  def stop : self
    return self unless @running.compare_and_set(true, false)

    Log.info { "Stopping Event::Loop" }

    @sources.each do |source|
      source.stop
      Log.debug { "Stopped source: #{source.name}" }
    end

    # Brief yield to allow fibers to exit gracefully
    # This prevents Channel::ClosedError in well-behaved sources
    sleep SHUTDOWN_TIMEOUT_MS.milliseconds / 10
    Fiber.yield

    @output.close unless @output.closed?
    Log.debug { "Output channel closed" }

    self
  end

  # Returns true if the event loop is currently running.
  def running? : Bool
    @running.get
  end

  # Returns the event output channel.
  #
  # Use this channel to receive events from all sources:
  # ```
  # while event = loop.output.receive?
  #   handle(event)
  # end
  # ```
  getter output : Channel(Any)

  # Returns the names of all registered sources.
  #
  # Useful for logging and debugging.
  def source_names : Array(String)
    @sources.map(&.name)
  end
end
