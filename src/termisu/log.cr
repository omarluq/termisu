require "log"

class Termisu
  # Termisu logging module.
  #
  # Provides structured logging for debugging terminal operations.
  # Logs are written to a file since stdout is used for terminal rendering.
  # Termisu loggers use an isolated registry, so host application logging
  # configuration neither receives nor controls Termisu entries.
  #
  # ## Configuration
  #
  # Environment variables:
  # - `TERMISU_LOG_LEVEL`: trace, debug, info, warn, error, fatal, none (default: debug)
  # - `TERMISU_LOG_FILE`: Path to log file (default: /tmp/termisu.log)
  # - `TERMISU_LOG_SYNC`: Dispatch mode (default: false)
  #   - `true`: Sync/direct mode - logs written immediately, ideal for debugging
  #   - `false`: Async mode - logs queued and buffered, better performance
  #
  # ## Dispatch Modes
  #
  # **Async mode** (default): Entries are queued to a fiber and file output is
  # buffered. The queue and file buffer are drained before the file is closed.
  #
  # **Sync mode**: Entries are written and flushed immediately for real-time
  # debugging and visibility during crashes.
  #
  # ## Example
  #
  # ```
  # # Use defaults (debug level, /tmp/termisu.log, async mode)
  # ./my_app
  #
  # # Disable logging
  # TERMISU_LOG_LEVEL=none ./my_app
  #
  # # Enable sync mode for real-time debugging
  # TERMISU_LOG_SYNC=true ./my_app
  # ```
  #
  # ## Usage in Termisu code
  #
  # ```
  # Termisu::Log.debug { "Input byte: #{byte}" }
  # Termisu::Logs::Terminal.trace { "Rendering cell at #{x},#{y}" }
  # ```

  # A dispatcher which reports asynchronous failures without abandoning its
  # queue. In particular, every drain barrier is acknowledged even if an
  # earlier write failed.
  private class AsyncLogDispatcher
    include ::Log::Dispatcher

    private record EntryMessage, entry : ::Log::Entry, backend : ::Log::Backend
    private record DrainMessage, done : Channel(Nil)
    private alias Message = EntryMessage | DrainMessage

    @channel : Channel(Message)
    @done : Channel(Nil)
    @first_error : Exception?

    def initialize(buffer_size : Int32 = 2048)
      @channel = Channel(Message).new(buffer_size)
      @done = Channel(Nil).new(1)
      @first_error = nil
      spawn(name: "termisu-log-dispatch") { write_logs }
    end

    def dispatch(entry : ::Log::Entry, backend : ::Log::Backend) : Nil
      @channel.send(EntryMessage.new(entry, backend))
    end

    def drain : Nil
      barrier = Channel(Nil).new(1)
      @channel.send(DrainMessage.new(barrier))
      barrier.receive
      raise_first_error
    end

    def close : Nil
      @channel.close
      @done.receive
      raise_first_error
    end

    private def write_logs : Nil
      while message = @channel.receive?
        case message
        in EntryMessage
          begin
            message.backend.write(message.entry)
          rescue ex
            @first_error ||= ex
          end
        in DrainMessage
          message.done.send(nil)
        end
      end
    ensure
      @done.send(nil)
    end

    private def raise_first_error : Nil
      if error = @first_error
        raise error
      end
    end
  end

  # IOBackend variant used by Termisu. Direct writes retain IOBackend's
  # immediate flush. Async writes leave flushing to explicit barriers/close so
  # File's output buffer can combine adjacent entries.
  private class FileLogBackend < ::Log::IOBackend
    @async : Bool
    @closing : Bool
    @dispatch_lock : Mutex

    def initialize(file : File, formatter : ::Log::Formatter, @async : Bool)
      dispatcher : ::Log::Dispatcher = if @async
        AsyncLogDispatcher.new
      else
        ::Log::DirectDispatcher
      end
      super(io: file, formatter: formatter, dispatcher: dispatcher)
      @closing = false
      @dispatch_lock = Mutex.new(:unchecked)
    end

    def dispatch(entry : ::Log::Entry) : Nil
      @dispatch_lock.synchronize do
        return if @closing
        dispatcher.dispatch(entry, self)
      end
    end

    def write(entry : ::Log::Entry) : Nil
      if @async
        format(entry)
        io.puts
      else
        super
      end
    end

    def flush : Nil
      first_error = nil.as(Exception?)

      @dispatch_lock.synchronize do
        if async_dispatcher = dispatcher.as?(AsyncLogDispatcher)
          begin
            async_dispatcher.drain
          rescue ex
            first_error = ex
          end
        end

        begin
          io.flush
        rescue ex
          first_error ||= ex
        end
      end

      if error = first_error
        raise error
      end
    end

    def close : Nil
      @dispatch_lock.synchronize do
        return if @closing
        @closing = true
        dispatcher.close
      end
    end
  end

  # Registry for loggers owned by Termisu. It deliberately does not use
  # `::Log.builder`, because host wildcard bindings on that builder must not
  # capture Termisu output.
  private class LogRegistry
    @logs = Hash(String, WeakRef(OwnedLog)).new
    @level = ::Log::Severity::None
    @backend : ::Log::Backend? = nil
    @mutex = Mutex.new(:unchecked)

    def for(source : String) : ::Log
      @mutex.synchronize do
        if log = @logs[source]?.try(&.value)
          return log
        end

        log = OwnedLog.new(source, self)
        log.backend = @backend
        log.initial_level = @level
        @logs[source] = WeakRef.new(log)
        log
      end
    end

    def bind(level : ::Log::Severity, backend : ::Log::Backend) : Nil
      @mutex.synchronize do
        @level = level
        @backend = backend
        each_log do |log|
          log.backend = backend
          log.initial_level = level
        end
      end
    end

    # Detaches only the resource passed by its owner. This identity check keeps
    # stale cleanup from unbinding a later setup cycle.
    def unbind(backend : ::Log::Backend) : Bool
      @mutex.synchronize do
        return false unless @backend.same?(backend)

        @backend = nil
        @level = ::Log::Severity::None
        each_log do |log|
          log.backend = nil
          log.initial_level = ::Log::Severity::None
        end
        true
      end
    end

    private def each_log(&) : Nil
      @logs.reject! { |_, log_ref| log_ref.value.nil? }
      @logs.each_value do |log_ref|
        if log = log_ref.value
          yield log
        end
      end
    end
  end

  # Log subclass whose child loggers remain in Termisu's isolated registry.
  private class OwnedLog < ::Log
    def initialize(source : String, @registry : LogRegistry)
      super(source, nil, ::Log::Severity::None)
    end

    def for(child_source : String, level : ::Log::Severity? = nil) : ::Log
      child = if source.blank?
                @registry.for(child_source)
              elsif child_source.blank?
                @registry.for(source)
              else
                @registry.for("#{source}.#{child_source}")
              end
      child.level = level if level
      child
    end

    def for(type : Class, level : ::Log::Severity? = nil) : ::Log
      child_source = type.name.underscore.gsub("::", ".")
      if paren = child_source.index('(')
        child_source = child_source[0...paren]
      end

      child = @registry.for(child_source)
      child.level = level if level
      child
    end

    # Owned logs are tracked by LogRegistry and are not members of the
    # process-global builder's weak-reference table.
    def finalize : Nil
    end
  end

  private LOGGER_REGISTRY = LogRegistry.new

  # Main log instance for Termisu library. `#for` creates another isolated
  # Termisu-owned logger rather than escaping to the host's global builder.
  Log = LOGGER_REGISTRY.for("termisu")

  # Logging configuration and lifecycle management.
  #
  # Handles setup, configuration, and cleanup of the logging system.
  # Called automatically by Termisu.new and Termisu.close.
  module Logging
    MUTEX = Mutex.new(:unchecked)

    # Open log file handle (nil when logging disabled)
    class_property log_file : File? = nil

    # Installed backend (nil when logging disabled or closed)
    class_property backend : ::Log::IOBackend? = nil

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
    # Setup failures retain the existing best-effort behavior: Termisu remains
    # usable with its isolated loggers disabled.
    def self.setup : Nil
      MUTEX.synchronize do
        return if configured?

        level_str = ENV.fetch("TERMISU_LOG_LEVEL", "debug").downcase
        level = LEVELS[level_str]? || ::Log::Severity::Debug

        if level == ::Log::Severity::None
          self.configured = true
          return
        end

        file = nil.as(File?)
        installed_backend = nil.as(FileLogBackend?)
        bound = false

        begin
          file_path = ENV.fetch("TERMISU_LOG_FILE", "/tmp/termisu.log")
          is_sync = ENV.fetch("TERMISU_LOG_SYNC", "false").downcase == "true"

          file = File.open(file_path, "a")
          file.sync = is_sync
          installed_backend = FileLogBackend.new(file, FORMATTER, async: !is_sync)
          LOGGER_REGISTRY.bind(level, installed_backend)
          bound = true

          self.log_file = file
          self.backend = installed_backend
          self.async_mode = !is_sync
          self.configured = true

          mode = is_sync ? "sync" : "async"
          Log.info { "Logging initialized: level=#{level}, file=#{file_path}, mode=#{mode}" }
        rescue
          LOGGER_REGISTRY.unbind(installed_backend) if bound && installed_backend
          installed_backend.try(&.close) rescue nil
          file.try(&.flush) rescue nil
          file.try(&.close) rescue nil
          self.log_file = nil
          self.backend = nil
          self.async_mode = false
          self.configured = true
        end
      end
    end

    # Unbinds Termisu loggers before draining their backend, then flushes and
    # closes the file. Every cleanup step runs and the first error is re-raised.
    def self.close : Nil
      error = nil.as(Exception?)

      MUTEX.synchronize do
        retained_backend = backend
        retained_file = log_file

        self.backend = nil
        self.log_file = nil
        self.async_mode = false
        self.configured = false

        if retained_backend
          error = capture_error(error) { LOGGER_REGISTRY.unbind(retained_backend) }
          error = capture_error(error) { retained_backend.close }
        end
        if retained_file
          error = capture_error(error) { retained_file.flush }
          error = capture_error(error) { retained_file.close }
        end
      end

      if exception = error
        raise exception
      end
    end

    # Drains all entries accepted before this call and flushes the file buffer.
    def self.flush : Nil
      MUTEX.synchronize do
        if installed_backend = backend
          installed_backend.as(FileLogBackend).flush
        elsif file = log_file
          file.flush
        end
      end
    end

    private def self.capture_error(error : Exception?, &) : Exception?
      yield
      error
    rescue ex
      error || ex
    end
  end

  # Component-specific log instances for fine-grained filtering.
  module Logs
    Terminal = LOGGER_REGISTRY.for("termisu.terminal")
    Buffer   = LOGGER_REGISTRY.for("termisu.buffer")
    Reader   = LOGGER_REGISTRY.for("termisu.reader")
    Render   = LOGGER_REGISTRY.for("termisu.render")
    Input    = LOGGER_REGISTRY.for("termisu.input")
    Color    = LOGGER_REGISTRY.for("termisu.color")
    Terminfo = LOGGER_REGISTRY.for("termisu.terminfo")
    Event    = LOGGER_REGISTRY.for("termisu.event")
  end
end

# Crystal's global builder has its own exit hook. Register Termisu separately
# so queued entries are drained even when an application omits `Termisu#close`.
at_exit { Termisu::Logging.close rescue nil }
