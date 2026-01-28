require "benchmark"
require "../src/termisu"
require "../src/termisu/time_compat"

# Concurrent benchmark runner infrastructure
#
# Features:
# - Runs benchmark suites concurrently using Crystal fibers
# - Captures benchmark results for flexible rendering
# - Lightweight measurement without external dependencies

module Termisu::Bench
  # Result from a single benchmark
  record BenchResult,
    name : String,
    iterations_per_second : Float64,
    mean_time : Time::Span,
    std_dev_percent : Float64,
    bytes_per_op : Int64

  # A group of related benchmarks
  record BenchGroup,
    name : String,
    results : Array(BenchResult)

  # Suite containing multiple groups
  record BenchSuite,
    name : String,
    groups : Array(BenchGroup)

  # Captures benchmark measurements
  class BenchCapture
    getter results : Array(BenchResult) = [] of BenchResult

    def report(name : String, &block)
      # Warmup
      100.times { block.call }

      # Measure
      iterations = 0
      measure_start = monotonic_now
      while (monotonic_now - measure_start) < 100.milliseconds
        block.call
        iterations += 1
      end
      elapsed = monotonic_now - measure_start

      ips = iterations.to_f64 / elapsed.total_seconds
      mean = elapsed / iterations

      @results << BenchResult.new(
        name: name,
        iterations_per_second: ips,
        mean_time: mean,
        std_dev_percent: 0.0, # Simplified - would need multiple runs
        bytes_per_op: 0_i64
      )
    end
  end

  # Concurrent benchmark runner utility
  class ConcurrentRunner
    @suites : Array(BenchSuite) = [] of BenchSuite
    @channel : Channel(BenchSuite)

    def initialize
      @channel = Channel(BenchSuite).new
    end

    def add_suite(name : String, &block : -> Array(BenchGroup))
      spawn do
        groups = block.call
        @channel.send(BenchSuite.new(name, groups))
      end
    end

    def run_all(count : Int32) : Array(BenchSuite)
      results = [] of BenchSuite
      count.times do
        results << @channel.receive
      end
      results
    end
  end
end
