require "log"

# Termisu logging module.
#
# Provides structured logging for debugging terminal operations.
# Logs are written to a file since stdout is used for terminal rendering.
#
# ## Configuration
#
# Environment variables:
# - `TERMISU_LOG_LEVEL`: trace, debug, info, warn, error, fatal, none (default: none)
# - `TERMISU_LOG_FILE`: Path to log file (default: termisu.log in current directory)
# - `TERMISU_LOG_SYNC`: Dispatch mode (default: true)
#   - `true`: Sync/direct mode - logs written immediately, ideal for debugging
#   - `false`: Async mode - logs queued to fiber, better performance
#
# ## Dispatch Modes
#
# **Sync mode** (default): Uses `Log::DispatchMode::Direct` for real-time logging.
# Logs appear immediately in the file, making it ideal for debugging crashes.
#
# **Async mode**: Uses `Log::DispatchMode::Async` for better performance.
# Logs are queued to a fiber and written asynchronously. Uses SafeFileIO
# wrapper to handle writes after file close, and Fiber.yield on close to
# allow pending logs to be processed.
#
# ## Example
#
# ```
# # Enable debug logging (sync mode for real-time output)
# TERMISU_LOG_LEVEL=debug TERMISU_LOG_FILE=/tmp/termisu.log ./my_app
#
# # Enable async mode for better performance
# TERMISU_LOG_LEVEL=debug TERMISU_LOG_FILE=/tmp/termisu.log TERMISU_LOG_SYNC=false ./my_app
# ```
#
# ## Usage in Termisu code
#
# ```
# Termisu::Log.debug { "Input byte: #{byte}" }
# Termisu::Logs::Terminal.trace { "Rendering cell at #{x},#{y}" }
# ```
class Termisu
  # Main log instance for Termisu library
  Log = ::Log.for("termisu")

  # IO wrapper that silently handles writes to closed streams.
  # Required for async dispatch mode to prevent errors when file closes
  # before async fiber finishes processing queued log messages.
  private class SafeFileIO < IO
    def initialize(@file : File)
    end

    def read(slice : Bytes) : Int32
      @file.read(slice)
    end

    def write(slice : Bytes) : Nil
      return if @file.closed?
      @file.write(slice)
    rescue IO::Error
      # Silently ignore writes to closed file from async dispatch
    end

    def close : Nil
      @file.close
    end

    def closed? : Bool
      @file.closed?
    end

    def flush : Nil
      @file.flush unless @file.closed?
    end
  end

  # Logging configuration and lifecycle management.
  #
  # Handles setup, configuration, and cleanup of the logging system.
  # Called automatically by Termisu.new and Termisu.close.
  module Logging
    # Open log file handle (nil when logging disabled)
    class_property log_file : File? = nil

    # Whether logging has been configured (prevents duplicate setup)
    class_property? configured : Bool = false

    # Whether async dispatch mode is enabled (affects close behavior)
    class_property? async_mode : Bool = false

    # Severity level name to Log::Severity mapping
    LEVELS = {
      "trace"  => ::Log::Severity::Trace,
      "debug"  => ::Log::Severity::Debug,
      "info"   => ::Log::Severity::Info,
      "notice" => ::Log::Severity::Notice,
      "warn"   => ::Log::Severity::Warn,
      "error"  => ::Log::Severity::Error,
      "fatal"  => ::Log::Severity::Fatal,
      "none"   => ::Log::Severity::None,
    }

    # Custom formatter for Termisu logs
    FORMATTER = ::Log::Formatter.new do |entry, io|
      io << entry.timestamp.to_s("%Y-%m-%d %H:%M:%S.%3N")
      io << " ["
      io << entry.severity.to_s.upcase.ljust(5)
      io << "] "
      io << entry.source
      io << ": "
      io << entry.message

      if data = entry.context
        data.each do |key, value|
          io << " " << key << "=" << value
        end
      end

      if ex = entry.exception
        io << "\n  Exception: " << ex.class.name << ": " << ex.message
        if bt = ex.backtrace?
          bt.first(5).each do |line|
            io << "\n    " << line
          end
        end
      end
    end

    # Configures logging based on environment variables.
    #
    # Reads TERMISU_LOG_LEVEL, TERMISU_LOG_FILE, and TERMISU_LOG_SYNC
    # to configure the logging backend. Called automatically by Termisu.new.
    #
    # In sync mode (default), uses direct dispatch for real-time logging.
    # In async mode, uses async dispatch with SafeFileIO wrapper.
    def self.setup
      return if configured?

      level_str = ENV.fetch("TERMISU_LOG_LEVEL", "none").downcase
      level = LEVELS[level_str]? || ::Log::Severity::None

      # Don't set up file logging if level is none
      if level == ::Log::Severity::None
        self.configured = true
        return
      end

      # Get log file path
      file_path = ENV.fetch("TERMISU_LOG_FILE", "termisu.log")

      begin
        file = File.open(file_path, "a")
        file.sync = true
        self.log_file = file

        # Choose dispatch mode: sync (direct) for real-time, async for performance
        sync_mode = ENV.fetch("TERMISU_LOG_SYNC", "true").downcase
        is_sync = sync_mode == "true"
        self.async_mode = !is_sync
        dispatch_mode = is_sync ? ::Log::DispatchMode::Direct : ::Log::DispatchMode::Async

        # Async mode needs SafeFileIO wrapper to handle writes after file close
        io : IO = is_sync ? file : SafeFileIO.new(file)
        backend = ::Log::IOBackend.new(io: io, formatter: FORMATTER, dispatcher: dispatch_mode)

        ::Log.setup("*", level, backend)

        mode = is_sync ? "sync" : "async"
        Log.info { "Logging initialized: level=#{level}, file=#{file_path}, mode=#{mode}" }
      rescue ex
        # If we can't open the log file, disable logging silently
      end

      self.configured = true
    end

    # Closes the log file and cleans up resources.
    #
    # In async mode, yields to let the dispatch fiber process pending
    # logs before closing. Called automatically by Termisu.close.
    def self.close
      if file = log_file
        if async_mode?
          3.times { Fiber.yield }
          file.flush rescue nil
        end
        file.close rescue nil
        self.log_file = nil
      end
    end

    # Flushes any buffered log entries to disk.
    #
    # In async mode, yields first to let dispatch fiber process.
    def self.flush
      Fiber.yield if async_mode?
      log_file.try(&.flush)
    end
  end

  # Component-specific log instances for fine-grained filtering.
  #
  # Each component has its own log source, allowing selective logging:
  # - termisu.terminal: Terminal initialization and screen management
  # - termisu.buffer: Cell buffer operations and rendering
  # - termisu.reader: Input reading and buffering
  # - termisu.input: Key/byte input processing
  # - termisu.terminfo: Terminfo database loading and capabilities
  module Logs
    Terminal = ::Log.for("termisu.terminal")
    Buffer   = ::Log.for("termisu.buffer")
    Reader   = ::Log.for("termisu.reader")
    Render   = ::Log.for("termisu.render")
    Input    = ::Log.for("termisu.input")
    Color    = ::Log.for("termisu.color")
    Terminfo = ::Log.for("termisu.terminfo")
  end
end
