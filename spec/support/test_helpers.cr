# Test helper classes for spec files.
#
# Contains utility classes that aid in testing but aren't
# mock implementations of production code.
module TestHelpers
  class RaisingLogIO < IO
    def read(slice : Bytes) : Int32
      0
    end

    def write(slice : Bytes) : Nil
      raise IO::Error.new("injected logging failure")
    end
  end

  def with_raising_lifecycle_logs(&)
    was_backend = Termisu::Logging.backend
    was_log_file = Termisu::Logging.log_file
    was_async = Termisu::Logging.async_mode?
    was_configured = Termisu::Logging.configured?
    loggers = [
      Termisu::Log,
      Termisu::Logs::Terminal,
      Termisu::Logs::Buffer,
      Termisu::Logs::Reader,
      Termisu::Logs::Render,
      Termisu::Logs::Input,
      Termisu::Logs::Color,
      Termisu::Logs::Terminfo,
      Termisu::Logs::Event,
    ] of ::Log
    previous_bindings = loggers.map { |logger| {logger.backend, logger.initial_level} }

    begin
      # Keep Logging.close inside the block from closing any real configured
      # resource while injecting failures only into Termisu-owned loggers.
      Termisu::Logging.backend = nil
      Termisu::Logging.log_file = nil
      Termisu::Logging.async_mode = false
      Termisu::Logging.configured = true
      backend = ::Log::IOBackend.new(
        io: RaisingLogIO.new,
        dispatcher: ::Log::DispatchMode::Direct,
      )
      loggers.each do |logger|
        logger.backend = backend
        logger.initial_level = ::Log::Severity::Trace
      end

      yield
    ensure
      loggers.zip(previous_bindings) do |logger, binding|
        logger.backend = binding[0]
        logger.initial_level = binding[1]
      end
      Termisu::Logging.backend = was_backend
      Termisu::Logging.log_file = was_log_file
      Termisu::Logging.async_mode = was_async
      Termisu::Logging.configured = was_configured
    end
  end

  # Helper class to hold mutable size values for testing.
  #
  # Crystal closures capture variables by reference, so modifying
  # these values will affect the size provider proc.
  #
  # Example:
  # ```
  # size = TestHelpers::MutableSize.new(80, 24)
  # provider = -> { size.to_tuple }
  #
  # # Later, change the size
  # size.width = 100
  # size.height = 50
  #
  # # provider.call now returns {100, 50}
  # ```
  class MutableSize
    property width : Int32
    property height : Int32

    def initialize(@width : Int32, @height : Int32)
    end

    def to_tuple : {Int32, Int32}
      {@width, @height}
    end
  end
end
