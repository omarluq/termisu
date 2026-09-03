require "../spec_helper"
require "file/tempfile"

private class LogSpecType
end

private class RaisingWriteLogIO < IO
  def read(slice : Bytes) : Int32
    0
  end

  def write(slice : Bytes) : Nil
    raise IO::Error.new("injected log write failure")
  end
end

private class RaisingFlushLogIO < IO
  getter contents : String { @memory.to_s }

  def initialize
    @memory = IO::Memory.new
  end

  def read(slice : Bytes) : Int32
    @memory.read(slice)
  end

  def write(slice : Bytes) : Nil
    @memory.write(slice)
  end

  def flush : Nil
    raise IO::Error.new("injected log flush failure")
  end
end

private class TrackingLogDispatcher
  include ::Log::Dispatcher

  getter close_count : Int32 = 0
  getter? file_open_during_close : Bool = false
  getter? logger_detached_during_close : Bool = false

  def initialize(@delegate : ::Log::Dispatcher, @file : File)
  end

  def dispatch(entry : ::Log::Entry, backend : ::Log::Backend) : Nil
    @delegate.dispatch(entry, backend)
  end

  def close : Nil
    @close_count += 1
    @file_open_during_close = !@file.closed?

    evaluated = false
    Termisu::Log.info do
      evaluated = true
      "must not be accepted while logging closes"
    end
    @logger_detached_during_close = !evaluated

    @delegate.close
    @file_open_during_close &&= !@file.closed?
  end
end

private class RaisingCloseLogDispatcher
  include ::Log::Dispatcher

  getter close_count : Int32 = 0

  def initialize(@delegate : ::Log::Dispatcher)
  end

  def dispatch(entry : ::Log::Entry, backend : ::Log::Backend) : Nil
    @delegate.dispatch(entry, backend)
  end

  def close : Nil
    @close_count += 1
    first_error = nil.as(Exception?)
    begin
      @delegate.close
    rescue ex
      first_error = ex
    end

    raise first_error if first_error
    raise IO::Error.new("injected backend close failure")
  end
end

private def with_log_environment(level : String, path : String, sync : Bool, &)
  previous_level = ENV["TERMISU_LOG_LEVEL"]?
  previous_file = ENV["TERMISU_LOG_FILE"]?
  previous_sync = ENV["TERMISU_LOG_SYNC"]?

  Termisu::Logging.close rescue nil
  ENV["TERMISU_LOG_LEVEL"] = level
  ENV["TERMISU_LOG_FILE"] = path
  ENV["TERMISU_LOG_SYNC"] = sync.to_s
  yield
ensure
  Termisu::Logging.close rescue nil

  if previous_level
    ENV["TERMISU_LOG_LEVEL"] = previous_level
  else
    ENV.delete("TERMISU_LOG_LEVEL")
  end
  if previous_file
    ENV["TERMISU_LOG_FILE"] = previous_file
  else
    ENV.delete("TERMISU_LOG_FILE")
  end
  if previous_sync
    ENV["TERMISU_LOG_SYNC"] = previous_sync
  else
    ENV.delete("TERMISU_LOG_SYNC")
  end
end

private def numbered_messages(path : String, prefix : String) : Array(Int32)
  File.read_lines(path).compact_map do |line|
    match = line.match(/#{prefix}-(\d+)/)
    match[1].to_i if match
  end
end

private def unbind_host(pattern : String, level : ::Log::Severity, backend : ::Log::Backend?) : Nil
  ::Log.builder.unbind(pattern, level, backend) if backend
rescue
  # A failed example may not have reached its bind.
end

describe Termisu::Logging do
  it "keeps host wildcard and scoped backends unchanged before, during, and after setup" do
    broad_backend = ::Log::MemoryBackend.new
    scoped_backend = ::Log::MemoryBackend.new
    broad_level = ::Log::Severity::Info
    scoped_level = ::Log::Severity::Debug
    host = ::Log.for("host.application")
    builder = ::Log.builder
    temp = File.tempfile("termisu-log-isolation", ".log")
    path = temp.path
    temp.close

    builder.bind("*", broad_level, broad_backend)
    builder.bind("host.*", scoped_level, scoped_backend)

    with_log_environment("debug", path, true) do
      host.info { "host-before" }
      Termisu::Log.info { "termisu-before" }

      Termisu::Logging.setup
      Termisu::Log.info { "termisu-root" }
      Termisu::Logs::Terminal.info { "termisu-component" }
      Termisu::Log.for("public-child").info { "termisu-public-child" }
      host.info { "host-during" }

      Termisu::Logging.close
      Termisu::Log.info { "termisu-after" }
      host.info { "host-after" }
    end

    broad_backend.entries.map(&.message).should eq(["host-before", "host-during", "host-after"])
    scoped_backend.entries.map(&.message).should eq(["host-before", "host-during", "host-after"])

    contents = File.read(path)
    contents.should contain("termisu-root")
    contents.should contain("termisu-component")
    contents.should contain("termisu-public-child")
    contents.should_not contain("host-before")
    contents.should_not contain("host-during")
    contents.should_not contain("host-after")
  ensure
    unbind_host("host.*", ::Log::Severity::Debug, scoped_backend)
    unbind_host("*", ::Log::Severity::Info, broad_backend)
    File.delete(path) if path && File.exists?(path)
  end

  it "makes none silent even when the host has a wildcard backend" do
    host_backend = ::Log::MemoryBackend.new
    builder = ::Log.builder
    temp = File.tempfile("termisu-log-none", ".log")
    path = temp.path
    temp.close
    File.delete(path)
    builder.bind("*", ::Log::Severity::Trace, host_backend)

    with_log_environment("none", path, false) do
      Termisu::Logging.setup
      evaluated = false
      Termisu::Log.for("none-child").fatal do
        evaluated = true
        "must stay silent"
      end

      evaluated.should be_false
      host_backend.entries.should be_empty
      File.exists?(path).should be_false
    end
  ensure
    unbind_host("*", ::Log::Severity::Trace, host_backend)
    File.delete(path) if path && File.exists?(path)
  end

  it "keeps public Log.for source behavior inside the isolated registry" do
    Termisu::Log.source.should eq("termisu")
    Termisu::Log.for("").should be(Termisu::Log)
    Termisu::Log.for("public").source.should eq("termisu.public")
    Termisu::Log.for(LogSpecType).source.should eq("log_spec_type")

    global = ::Log.for("termisu.public")
    Termisu::Log.for("public").should_not be(global)
  end

  [true, false].each do |sync|
    mode = sync ? "direct" : "async"

    it "writes complete ordered numbered messages in #{mode} mode" do
      temp = File.tempfile("termisu-log-#{mode}", ".log")
      path = temp.path
      temp.close

      with_log_environment("debug", path, sync) do
        Termisu::Logging.setup
        count = 500
        count.times { |number| Termisu::Log.info { "#{mode}-numbered-#{number}" } }
        Termisu::Logging.close

        numbered_messages(path, "#{mode}-numbered").should eq((0...count).to_a)
      end
    ensure
      File.delete(path) if path && File.exists?(path)
    end
  end

  it "makes direct entries visible immediately and enables file buffering only for async mode" do
    direct = File.tempfile("termisu-log-direct-visible", ".log")
    direct_path = direct.path
    direct.close
    async = File.tempfile("termisu-log-async-buffered", ".log")
    async_path = async.path
    async.close

    with_log_environment("debug", direct_path, true) do
      Termisu::Logging.setup
      file = Termisu::Logging.log_file || fail("logging did not open its file")
      file.sync?.should be_true
      Termisu::Log.info { "direct-visible-now" }
      File.read(direct_path).should contain("direct-visible-now")
    end

    with_log_environment("debug", async_path, false) do
      Termisu::Logging.setup
      file = Termisu::Logging.log_file || fail("logging did not open its file")
      file.sync?.should be_false
      Termisu::Log.info { "async-buffered" }
      Termisu::Logging.flush
      File.read(async_path).should contain("async-buffered")
    end
  ensure
    File.delete(direct_path) if direct_path && File.exists?(direct_path)
    File.delete(async_path) if async_path && File.exists?(async_path)
  end

  it "drains async entries from the process-exit hook" do
    temp = File.tempfile("termisu-log-process-exit", ".log")
    path = temp.path
    temp.close
    fixture = File.expand_path("../fixtures/log_process_exit.cr", __DIR__)

    output = IO::Memory.new
    error = IO::Memory.new
    status = Process.run(
      "crystal",
      ["run", fixture],
      output: output,
      error: error,
      env: {
        "TERMISU_LOG_LEVEL" => "debug",
        "TERMISU_LOG_FILE"  => path,
        "TERMISU_LOG_SYNC"  => "false",
      }
    )

    status.success?.should be_true,
      "process-exit fixture failed (#{status.exit_code})\nstdout:\n#{output}\nstderr:\n#{error}"
    numbered_messages(path, "exit-numbered").should eq((0...500).to_a)
  ensure
    File.delete(path) if path && File.exists?(path)
  end

  it "disables logging without changing host configuration when setup cannot open its file" do
    host_backend = ::Log::MemoryBackend.new
    builder = ::Log.builder
    host = ::Log.for("host.setup-failure")
    path = File.join(Dir.tempdir, "missing-termisu-log-dir-#{Random.rand(UInt64)}", "output.log")
    builder.bind("*", ::Log::Severity::Info, host_backend)

    with_log_environment("debug", path, false) do
      Termisu::Logging.setup
      Termisu::Logging.configured?.should be_true
      Termisu::Logging.backend.should be_nil
      Termisu::Logging.log_file.should be_nil

      evaluated = false
      Termisu::Log.info do
        evaluated = true
        "disabled after setup failure"
      end
      evaluated.should be_false

      host.info { "host survives setup failure" }
      host_backend.entries.map(&.message).should eq(["host survives setup failure"])
    end
  ensure
    unbind_host("*", ::Log::Severity::Info, host_backend)
  end

  it "drains after async write failures, closes resources, and reports the first error" do
    temp = File.tempfile("termisu-log-write-failure", ".log")
    path = temp.path
    temp.close

    with_log_environment("debug", path, false) do
      Termisu::Logging.setup
      file = Termisu::Logging.log_file || fail("logging did not open its file")
      backend = Termisu::Logging.backend || fail("logging did not install its backend")
      backend.io = RaisingWriteLogIO.new
      dispatcher = RaisingCloseLogDispatcher.new(backend.dispatcher)
      backend.dispatcher = dispatcher
      Termisu::Log.info { "write fails asynchronously" }

      expect_raises(IO::Error, "injected log write failure") { Termisu::Logging.close }
      dispatcher.close_count.should eq(1)
      file.closed?.should be_true
      Termisu::Logging.backend.should be_nil
      Termisu::Logging.log_file.should be_nil
      Termisu::Logging.configured?.should be_false

      Termisu::Logging.close
    end
  ensure
    File.delete(path) if path && File.exists?(path)
  end

  it "uses a drain barrier before reporting flush failures" do
    temp = File.tempfile("termisu-log-flush-failure", ".log")
    path = temp.path
    temp.close

    with_log_environment("debug", path, false) do
      Termisu::Logging.setup
      file = Termisu::Logging.log_file || fail("logging did not open its file")
      backend = Termisu::Logging.backend || fail("logging did not install its backend")
      failing_io = RaisingFlushLogIO.new
      backend.io = failing_io
      20.times { |number| Termisu::Log.info { "flush-before-error-#{number}" } }

      expect_raises(IO::Error, "injected log flush failure") { Termisu::Logging.flush }
      (0...20).each { |number| failing_io.contents.should contain("flush-before-error-#{number}") }

      backend.io = file
      Termisu::Logging.close
    end
  ensure
    File.delete(path) if path && File.exists?(path)
  end

  it "unbinds before draining and closes each backend once before its file across cycles" do
    temp = File.tempfile("termisu-logging-lifecycle", ".log")
    path = temp.path
    temp.close

    with_log_environment("debug", path, false) do
      2.times do |cycle|
        Termisu::Logging.setup
        file = Termisu::Logging.log_file || fail("logging did not open its file")
        backend = Termisu::Logging.backend || fail("logging did not retain its backend")
        dispatcher = TrackingLogDispatcher.new(backend.dispatcher, file)
        backend.dispatcher = dispatcher

        Termisu::Log.info { "logging lifecycle cycle #{cycle}" }
        close_results = Channel(Exception?).new(8)
        8.times do
          spawn do
            error = nil.as(Exception?)
            begin
              Termisu::Logging.close
            rescue ex
              error = ex
            end
            close_results.send(error)
          end
        end
        8.times { close_results.receive.should be_nil }
        Termisu::Logging.close

        dispatcher.close_count.should eq(1)
        dispatcher.file_open_during_close?.should be_true
        dispatcher.logger_detached_during_close?.should be_true
        file.closed?.should be_true
        Termisu::Logging.backend.should be_nil
        Termisu::Logging.log_file.should be_nil
        Termisu::Logging.configured?.should be_false
      end
    end

    contents = File.read(path)
    contents.should contain("logging lifecycle cycle 0")
    contents.should contain("logging lifecycle cycle 1")
  ensure
    File.delete(path) if path && File.exists?(path)
  end

  it "continues file cleanup after a backend close failure and keeps close idempotent" do
    temp = File.tempfile("termisu-log-close-failure", ".log")
    path = temp.path
    temp.close

    with_log_environment("debug", path, false) do
      Termisu::Logging.setup
      file = Termisu::Logging.log_file || fail("logging did not open its file")
      backend = Termisu::Logging.backend || fail("logging did not install its backend")
      dispatcher = RaisingCloseLogDispatcher.new(backend.dispatcher)
      backend.dispatcher = dispatcher
      Termisu::Log.info { "entry before close failure" }

      expect_raises(IO::Error, "injected backend close failure") { Termisu::Logging.close }
      dispatcher.close_count.should eq(1)
      file.closed?.should be_true
      Termisu::Logging.backend.should be_nil
      Termisu::Logging.log_file.should be_nil
      Termisu::Logging.configured?.should be_false

      Termisu::Logging.close
      dispatcher.close_count.should eq(1)
    end
  ensure
    File.delete(path) if path && File.exists?(path)
  end
end
