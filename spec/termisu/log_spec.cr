require "../spec_helper"
require "file/tempfile"

private class TrackingLogDispatcher
  include ::Log::Dispatcher

  getter close_count : Int32 = 0
  getter? file_open_during_close : Bool = false

  def initialize(@delegate : ::Log::Dispatcher, @file : File)
  end

  def dispatch(entry : ::Log::Entry, backend : ::Log::Backend) : Nil
    @delegate.dispatch(entry, backend)
  end

  def close : Nil
    @close_count += 1
    @file_open_during_close = !@file.closed?
    @delegate.close
    @file_open_during_close &&= !@file.closed?
  end
end

describe Termisu::Logging do
  it "closes each retained backend exactly once before its file across setup cycles" do
    previous_level = ENV["TERMISU_LOG_LEVEL"]?
    previous_file = ENV["TERMISU_LOG_FILE"]?
    previous_sync = ENV["TERMISU_LOG_SYNC"]?
    temp = File.tempfile("termisu-logging", ".log")
    path = temp.path
    temp.close

    ENV["TERMISU_LOG_LEVEL"] = "debug"
    ENV["TERMISU_LOG_FILE"] = path
    ENV["TERMISU_LOG_SYNC"] = "false"

    2.times do |cycle|
      Termisu::Logging.setup
      file = Termisu::Logging.log_file || fail("logging did not open its file")
      backend = Termisu::Logging.backend || fail("logging did not retain its backend")
      dispatcher = TrackingLogDispatcher.new(backend.dispatcher, file)
      backend.dispatcher = dispatcher

      Termisu::Log.info { "logging lifecycle cycle #{cycle}" }
      Termisu::Logging.close
      Termisu::Logging.close

      dispatcher.close_count.should eq(1)
      dispatcher.file_open_during_close?.should be_true
      file.closed?.should be_true
      Termisu::Logging.backend.should be_nil
      Termisu::Logging.log_file.should be_nil
      Termisu::Logging.configured?.should be_false
    end

    contents = File.read(path)
    contents.should contain("logging lifecycle cycle 0")
    contents.should contain("logging lifecycle cycle 1")
  ensure
    Termisu::Logging.close
    File.delete(path) if path && File.exists?(path)

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
end
