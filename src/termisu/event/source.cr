# Abstract base class for event sources.
#
# An Event::Source produces events and sends them to a shared channel.
# Subclasses implement specific event generation logic (input, timer, resize).
#
# ## Implementing an Event::Source
#
# Subclasses must implement four abstract methods:
# - `start(output)` - Begin producing events to the channel
# - `stop` - Stop producing events
# - `running?` - Return current running state
# - `name` - Return a descriptive name for logging
#
# ## Thread Safety
#
# Implementations should use `Atomic(Bool)` for the running state
# and `compare_and_set` to prevent double-start issues.
#
# ## Example
#
# ```
# class MySource < Termisu::Event::Source
#   @running = Atomic(Bool).new(false)
#   @fiber : Fiber?
#
#   def start(output : Channel(Event::Any)) : Nil
#     return unless @running.compare_and_set(false, true)
#     @fiber = spawn(name: "my-source") do
#       while @running.get
#         # Generate and send events
#         output.send(my_event) rescue break
#         sleep 100.milliseconds
#       end
#     end
#   end
#
#   def stop : Nil
#     @running.set(false)
#   end
#
#   def running? : Bool
#     @running.get
#   end
#
#   def name : String
#     "my-source"
#   end
# end
# ```
abstract class Termisu::Event::Source
  # Starts producing events to the output channel.
  #
  # The source should spawn a fiber to produce events asynchronously.
  # Events are sent to the provided channel.
  #
  # Implementations should:
  # - Use `compare_and_set(false, true)` to prevent double-start
  # - Spawn a named fiber for debugging: `spawn(name: "termisu-xxx")`
  # - Handle `Channel::ClosedError` gracefully when sending
  # - Check `running?` in the event loop to enable clean shutdown
  abstract def start(output : Channel(Event::Any)) : Nil

  # Stops producing events.
  #
  # Sets the running state to false, signaling the fiber to exit.
  # This should be a quick, non-blocking operation.
  # The actual fiber cleanup happens on the next loop iteration.
  abstract def stop : Nil

  # Returns true if this source is currently running.
  #
  # Used to check state and control the event production loop.
  abstract def running? : Bool

  # Returns a descriptive name for this source.
  #
  # Used for logging, debugging, and identifying sources in the Event::Loop.
  # Examples: "input", "resize", "timer", "custom-network"
  abstract def name : String
end
