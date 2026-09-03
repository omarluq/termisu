require "benchmark"
require "../src/termisu"
require "../src/termisu/time_compat"

module Termisu::Bench
  # Measurement settings. A sample times one batch, never each operation.
  record BenchConfig, samples : Int32, sample_time : Time::Span do
    MIN_SAMPLES = 5

    def initialize(@samples : Int32 = 8, @sample_time : Time::Span = 50.milliseconds)
      raise ArgumentError.new("samples must be at least #{MIN_SAMPLES}") if @samples < MIN_SAMPLES
      raise ArgumentError.new("sample time must be positive") unless @sample_time > Time::Span.zero
    end

    def self.from_env : self
      samples = ENV.fetch("TERMISU_BENCH_SAMPLES", "8").to_i
      sample_ms = ENV.fetch("TERMISU_BENCH_SAMPLE_MS", "50").to_f
      new(samples, sample_ms.milliseconds)
    end
  end

  # Work performed by a sample, separate from GC allocation accounting.
  record BenchMetrics,
    mutations : UInt64,
    emitted_bytes : UInt64,
    string_writes : UInt64,
    byte_writes : UInt64,
    callback_calls : UInt64,
    flushes : UInt64 do
    def self.empty : self
      new(0_u64, 0_u64, 0_u64, 0_u64, 0_u64, 0_u64)
    end

    def +(other : self) : self
      self.class.new(
        mutations + other.mutations,
        emitted_bytes + other.emitted_bytes,
        string_writes + other.string_writes,
        byte_writes + other.byte_writes,
        callback_calls + other.callback_calls,
        flushes + other.flushes
      )
    end
  end

  # One raw batch measurement. Allocation bytes come from Benchmark.memory.
  record BenchSample,
    iterations : Int32,
    elapsed : Time::Span,
    allocated_bytes : Int64,
    metrics : BenchMetrics do
    def iterations_per_second : Float64
      iterations.to_f64 / elapsed.total_seconds
    end

    def bytes_per_operation : Float64
      allocated_bytes.to_f64 / iterations
    end
  end

  # Result from one benchmark job, including its complete raw distribution.
  record BenchResult,
    name : String,
    iterations_per_second : Float64,
    mean_time : Time::Span,
    std_dev_percent : Float64,
    bytes_per_op : Float64,
    samples : Array(BenchSample),
    metrics : BenchMetrics

  # A group of related benchmarks.
  record BenchGroup,
    name : String,
    results : Array(BenchResult)

  # Suite containing multiple groups.
  record BenchSuite,
    name : String,
    groups : Array(BenchGroup)

  # Observable destination for pure benchmark results. This prevents a result
  # from becoming dead work without allocating in zero-allocation controls.
  module BenchSink
    extend self

    @@value = 0_u64

    def consume(value : Bytes) : Nil
      identity = value.to_unsafe.address.to_u64 ^ value.size.to_u64
      @@value &+= identity
    end

    def consume(value : Reference) : Nil
      @@value &+= value.object_id.to_u64
    end

    def consume(value) : Nil
      @@value &+= value.hash.to_u64
    end

    def value : UInt64
      @@value
    end
  end

  # Captures repeated batch measurements in report order.
  class BenchCapture
    getter results : Array(BenchResult) = [] of BenchResult

    def initialize(@config : BenchConfig = BenchConfig.from_env)
    end

    def report(
      name : String,
      before_sample : (-> Nil)? = nil,
      sample_metrics : (-> BenchMetrics)? = nil,
      validate_sample : (BenchSample -> Nil)? = nil,
      mutations_per_iteration : Bool = false,
      &block : -> T
    ) forall T
      action = -> { BenchSink.consume(block.call) }
      iterations = calibrate(action)
      samples = Array(BenchSample).new(@config.samples)

      @config.samples.times do
        before_sample.try(&.call)
        GC.collect

        elapsed = Time::Span.zero
        allocated_bytes = Benchmark.memory do
          elapsed = Time.measure { iterations.times { action.call } }
        end
        metrics = sample_metrics.try(&.call) || BenchMetrics.empty

        if mutations_per_iteration && metrics.mutations != iterations.to_u64
          raise "#{name}: expected #{iterations} mutations, observed #{metrics.mutations}"
        end

        sample = BenchSample.new(iterations, elapsed, allocated_bytes, metrics)
        validate_sample.try(&.call(sample))
        samples << sample
      end

      @results << summarize(name, samples)
    end

    # Calibrate with exponentially larger batches. Clock reads occur around a
    # batch only; the measured operation itself never samples the clock.
    private def calibrate(action : -> Nil) : Int32
      iterations = 1

      loop do
        elapsed = Time.measure { iterations.times { action.call } }
        return iterations if elapsed >= @config.sample_time
        return iterations if iterations > Int32::MAX // 2

        iterations *= 2
      end
    end

    private def summarize(name : String, samples : Array(BenchSample)) : BenchResult
      rates = samples.map(&.iterations_per_second)
      mean_rate = rates.sum / rates.size
      variance = rates.sum { |rate| (rate - mean_rate) ** 2 } / rates.size
      deviation = mean_rate.zero? ? 0.0 : Math.sqrt(variance) * 100.0 / mean_rate
      total_iterations = samples.sum(0_i64, &.iterations.to_i64)
      total_elapsed = samples.sum(Time::Span.zero, &.elapsed)
      allocated_bytes = samples.sum(0_i64, &.allocated_bytes)
      metrics = samples.reduce(BenchMetrics.empty) { |sum, sample| sum + sample.metrics }

      BenchResult.new(
        name,
        mean_rate,
        total_elapsed / total_iterations,
        deviation,
        allocated_bytes.to_f64 / total_iterations,
        samples,
        metrics
      )
    end
  end

  # Compatibility utility for future yielding/I/O suites. Suites may overlap,
  # while returned results always retain registration order. CPU benchmarks do
  # not use this runner because fibers cannot make those measurements parallel.
  class ConcurrentRunner
    alias Outcome = BenchSuite | Exception

    @channel = Channel(NamedTuple(index: Int32, outcome: Outcome)).new
    @completed = {} of Int32 => Outcome
    @next_index = 0
    @next_result_index = 0

    def add_suite(name : String, &block : -> Array(BenchGroup)) : Nil
      index = @next_index
      @next_index += 1

      spawn do
        outcome = begin
          BenchSuite.new(name, block.call)
        rescue error
          error
        end
        @channel.send({index: index, outcome: outcome})
      end
    end

    # Consume exactly count suites in registration order. A later suite may
    # finish first; retain it until an earlier partial run_all call consumes
    # the preceding registrations.
    def run_all(count : Int32) : Array(BenchSuite)
      available = @next_index - @next_result_index
      unless count >= 0 && count <= available
        raise ArgumentError.new("count must be between 0 and #{available}")
      end

      last_index = @next_result_index + count
      until (@next_result_index...last_index).all? { |index| @completed.has_key?(index) }
        result = @channel.receive
        @completed[result[:index]] = result[:outcome]
      end

      outcomes = Array(Outcome).new(count) do |offset|
        @completed.delete(@next_result_index + offset) || raise "concurrent suite result missing"
      end
      @next_result_index = last_index
      outcomes.map do |outcome|
        raise outcome if outcome.is_a?(Exception)
        outcome
      end
    end
  end
end
