# Reproducible end-to-end input readiness latency probe.
#
# Workload: after 100 warmups, write one ASCII byte to a pipe and measure from
# immediately before write(2) until Input delivers the parsed key to a waiting
# channel consumer. Samples are serialized so no prior byte is outstanding.
# This includes worker, scheduler, parser, and channel wakeup latency.
#
# Usage: crystal run --release bench/input_readiness_latency.cr -- [samples] [--raw]
require "../src/termisu"

private def measure_input_latency(samples : Int32) : Array(Int64)
  descriptors = StaticArray(Int32, 2).new(0)
  raise IO::Error.from_errno("pipe") unless LibC.pipe(descriptors) == 0
  read_fd, write_fd = descriptors

  begin
    reader = Termisu::Reader.new(read_fd)
    parser = Termisu::Input::Parser.new(reader)
    source = Termisu::Event::Source::Input.new(reader, parser)
    channel = Channel(Termisu::Event::Any).new(1)
    latencies = Array(Int64).new(samples)

    begin
      source.start(channel)
      (samples + 100).times do |index|
        started = monotonic_now
        raise IO::Error.from_errno("write") unless LibC.write(write_fd, "x".to_unsafe, 1) == 1
        event = channel.receive.as(Termisu::Event::Key)
        raise "unexpected input event" unless event.char == 'x'
        elapsed = (monotonic_now - started).total_nanoseconds.to_i64
        latencies << elapsed if index >= 100
      end
    ensure
      source.stop
      channel.close
      reader.close
    end

    latencies
  ensure
    LibC.close(read_fd)
    LibC.close(write_fd)
  end
end

samples = ARGV.find(&.to_i?).try(&.to_i) || 500
abort "samples must be positive" unless samples > 0
raw = ARGV.includes?("--raw")
latencies = measure_input_latency(samples)
sorted = latencies.sort
percentile = ->(fraction : Float64) do
  index = ((sorted.size - 1) * fraction).round.to_i
  sorted[index] / 1_000.0
end

puts "samples=#{samples} unit=us workload=pipe_write_to_parsed_channel_receive"
puts "p50=#{percentile.call(0.50)} p95=#{percentile.call(0.95)} p99=#{percentile.call(0.99)}"
puts latencies.join(',') if raw
