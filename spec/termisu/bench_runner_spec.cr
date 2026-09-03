require "../spec_helper"
require "../../bench/suites/buffer_suite"

private def fast_bench_config
  Termisu::Bench::BenchConfig.new(5, 50.microseconds)
end

describe Termisu::Bench::BenchSink do
  it "consumes constant-cost identities instead of payload-dependent hashes" do
    reference = "reference payload"
    bytes = Bytes[1, 2, 3]
    before = Termisu::Bench::BenchSink.value

    Termisu::Bench::BenchSink.consume(reference)
    Termisu::Bench::BenchSink.consume(bytes)

    byte_identity = bytes.to_unsafe.address.to_u64 ^ bytes.size.to_u64
    expected = before &+ reference.object_id.to_u64 &+ byte_identity
    Termisu::Bench::BenchSink.value.should eq(expected)
  end
end

describe Termisu::Bench::BenchCapture do
  it "retains repeated raw samples in report order" do
    capture = Termisu::Bench::BenchCapture.new(fast_bench_config)
    value = 0_u64

    capture.report("first") { value &+= 1 }
    capture.report("second") { value &+= 1 }

    capture.results.map(&.name).should eq(["first", "second"])
    capture.results.each do |result|
      result.samples.size.should eq(5)
      result.samples.each do |sample|
        sample.iterations.should be > 0
        sample.elapsed.should be > Time::Span.zero
      end
    end
  end

  it "counts only mutations proved from observable Buffer state" do
    capture = Termisu::Bench::BenchCapture.new(fast_bench_config)
    probe = Termisu::Bench::MutationProbe.new
    buffer = Termisu::Buffer.new(1, 1)
    expected_a = Termisu::Cell.new("A")
    expected_b = Termisu::Cell.new("B")
    alternate = false

    capture.report(
      "A/B mutation",
      before_sample: -> { probe.reset },
      sample_metrics: -> { probe.metrics },
      mutations_per_iteration: true
    ) do
      alternate = !alternate
      before = buffer.get_cell(0, 0).as(Termisu::Cell)
      expected = alternate ? expected_a : expected_b
      buffer.set_cell(0, 0, expected.grapheme)
      probe.observe_cell_change(buffer, 0, 0, before, expected)
    end

    capture.results.first.samples.each do |sample|
      sample.metrics.mutations.should eq(sample.iterations.to_u64)
    end

    current = buffer.get_cell(0, 0).as(Termisu::Cell)
    expect_raises(Exception, /did not produce the expected state/) do
      probe.observe_cell_change(buffer, 0, 0, current, current)
    end
  end

  it "reports measured allocation rather than placeholder values" do
    capture = Termisu::Bench::BenchCapture.new(fast_bench_config)
    state = 0_u64

    capture.report("zero") do
      state &+= 1
      state &* 3_u64
    end
    capture.report("allocating") { Bytes.new(64, (state & 0xff).to_u8) }

    capture.results[0].bytes_per_op.should eq(0.0)
    capture.results[1].bytes_per_op.should be > 0.0
    capture.results[1].samples.sum(&.allocated_bytes).should be > 0
  end
end

describe Termisu::Bench::BufferSuite do
  it "validates every real stateful job and its rendered payload" do
    groups = Termisu::Bench::BufferSuite.run(fast_bench_config)
    results = groups.flat_map(&.results)

    results.map(&.name).should eq([
      "set_cell (small)",
      "set_cell (large)",
      "set_cell with attrs",
      "refill + clear (small)",
      "refill + clear (medium)",
      "refill + clear (large)",
      "fill small A/B (80x24)",
      "fill medium A/B (120x40)",
      "render_to (no changes)",
      "render_to (1 cell A/B)",
      "render_to (10% A/B)",
      "sync (small)",
      "sync (medium)",
      "sync (large)",
      "resize alternating 80x24 / 120x40",
      "construct + resize grow",
      "resize same (no-op control)",
    ])

    stateful_names = [
      "set_cell (small)",
      "set_cell (large)",
      "set_cell with attrs",
      "refill + clear (small)",
      "refill + clear (medium)",
      "refill + clear (large)",
      "fill small A/B (80x24)",
      "fill medium A/B (120x40)",
      "render_to (1 cell A/B)",
      "render_to (10% A/B)",
      "resize alternating 80x24 / 120x40",
      "construct + resize grow",
    ]
    stateful_names.each do |name|
      result = results.find! { |candidate| candidate.name == name }
      result.samples.each do |sample|
        sample.metrics.mutations.should eq(sample.iterations.to_u64)
      end
    end

    expected_bytes = {
      "render_to (no changes)" => 0_u64,
      "render_to (1 cell A/B)" => 1_u64,
      "render_to (10% A/B)"    => 192_u64,
      "sync (small)"           => 80_u64 * 24,
      "sync (medium)"          => 120_u64 * 40,
      "sync (large)"           => 200_u64 * 60,
    }
    expected_bytes.each do |name, bytes_per_iteration|
      result = results.find! { |candidate| candidate.name == name }
      result.samples.each do |sample|
        sample.metrics.emitted_bytes.should eq(bytes_per_iteration * sample.iterations.to_u64)
        sample.metrics.string_writes.should eq(0_u64)
        sample.metrics.flushes.should eq(sample.iterations.to_u64)
      end
    end
  end
end

describe Termisu::Bench::NullRenderer do
  it "counts String and production-like Bytes writes separately" do
    renderer = Termisu::Bench::NullRenderer.new

    renderer.write("abc")
    renderer.write(Bytes[1, 2, 3, 4])
    renderer.move_cursor(1, 2)
    renderer.flush

    renderer.metrics.should eq(Termisu::Bench::BenchMetrics.new(
      mutations: 0_u64,
      emitted_bytes: 7_u64,
      string_writes: 1_u64,
      byte_writes: 1_u64,
      callback_calls: 1_u64,
      flushes: 1_u64
    ))
  end

  it "receives Buffer payload through Bytes without materializing a String" do
    renderer = Termisu::Bench::NullRenderer.new
    renderer.expect_uniform_payload('A'.ord.to_u8)
    buffer = Termisu::Buffer.new(1, 1)
    buffer.set_cell(0, 0, 'A').should be_true

    buffer.render_to(renderer)

    renderer.emitted_bytes.should eq(1_u64)
    renderer.string_writes.should eq(0_u64)
    renderer.byte_writes.should eq(1_u64)
    renderer.flushes.should eq(1_u64)
  end

  it "rejects an unexpected rendered payload" do
    renderer = Termisu::Bench::NullRenderer.new
    renderer.expect_uniform_payload('A'.ord.to_u8)

    expect_raises(Exception, /unexpected payload/) do
      renderer.write(Bytes['B'.ord.to_u8])
    end
  end
end

describe Termisu::Bench::ConcurrentRunner do
  it "buffers out-of-order completions across partial run_all calls" do
    runner = Termisu::Bench::ConcurrentRunner.new
    started = Channel(String).new
    second_completed = Channel(Nil).new
    release_first = Channel(Nil).new
    executions = Hash(String, Int32).new(0)

    runner.add_suite("first") do
      started.send("first")
      release_first.receive
      executions["first"] += 1
      [] of Termisu::Bench::BenchGroup
    end
    runner.add_suite("second") do
      started.send("second")
      executions["second"] += 1
      second_completed.send(nil)
      [] of Termisu::Bench::BenchGroup
    end

    outcome = Channel(Array(Termisu::Bench::BenchSuite) | Exception).new
    spawn do
      outcome.send(runner.run_all(1))
    rescue error
      outcome.send(error)
    end

    2.times { started.receive }
    second_completed.receive
    # Let the second suite return and deliver its out-of-window result while
    # the first suite remains blocked on the explicit barrier.
    Fiber.yield
    Fiber.yield
    release_first.send(nil)
    first = outcome.receive
    first.should be_a(Array(Termisu::Bench::BenchSuite))
    first.as(Array(Termisu::Bench::BenchSuite)).map(&.name).should eq(["first"])

    runner.run_all(1).map(&.name).should eq(["second"])
    executions.should eq({"first" => 1, "second" => 1})
  end

  it "propagates suite failures instead of waiting forever" do
    runner = Termisu::Bench::ConcurrentRunner.new
    runner.add_suite("broken") do
      raise "suite failed"
    end

    expect_raises(Exception, "suite failed") { runner.run_all(1) }
  end
end
