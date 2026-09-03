# Disable logging during benchmarks for clean output.
ENV["TERMISU_LOG_LEVEL"] = "none"

require "log"

Log.setup(:none)

require "./bench_runner"
require "./suites/buffer_suite"
require "./suites/color_suite"
require "./suites/parser_suite"

# Usage:
#   crystal run bench/run.cr --release
# For process-level distributions, invoke the release binary at least five
# times and set TERMISU_BENCH_RUN and TERMISU_BENCH_AFFINITY to describe the
# externally controlled run/affinity environment.
module Termisu::Bench
  module ANSIColors
    RESET        = "\e[0m"
    BOLD         = "\e[1m"
    GREEN        = "\e[32m"
    YELLOW       = "\e[33m"
    BLUE         = "\e[34m"
    MAGENTA      = "\e[35m"
    CYAN         = "\e[36m"
    WHITE        = "\e[37m"
    BRIGHT_GREEN = "\e[92m"
  end

  # Truth controls for Benchmark.memory. These stay in normal benchmark output
  # so a runtime/toolchain that cannot distinguish them fails loudly.
  module AllocationControlSuite
    extend self

    def run(config : BenchConfig = BenchConfig.from_env) : Array(BenchGroup)
      capture = BenchCapture.new(config)
      state = 0_u64

      capture.report("zero-allocation control") do
        state &+= 1
        state &* 17_u64
      end

      capture.report("allocating control") do
        state &+= 1
        "x" * (32 + (state & 1).to_i)
      end

      zero = capture.results[0]
      allocating = capture.results[1]
      unless zero.samples.all?(&.allocated_bytes.zero?)
        raise "zero-allocation control allocated #{zero.bytes_per_op} B/op"
      end
      unless allocating.samples.all? { |sample| sample.allocated_bytes > 0 }
        raise "allocating control reported a zero-allocation sample"
      end

      [BenchGroup.new("Allocation Controls", capture.results)]
    end
  end

  class TextRenderer
    include ANSIColors

    def render_header(title : String, config : BenchConfig) : Nil
      puts "#{CYAN}#{BOLD}╔#{"═" * 62}╗#{RESET}"
      puts "#{CYAN}#{BOLD}║#{title.center(62)}║#{RESET}"
      puts "#{CYAN}#{BOLD}╠#{"═" * 62}╣#{RESET}"
      header_field("Crystal", Crystal::VERSION)
      header_field("LLVM", Crystal::LLVM_VERSION)
      header_field("Build", BUILD_MODE)
      header_field("Process", Process.pid.to_s)
      header_field("Run", ENV.fetch("TERMISU_BENCH_RUN", "unspecified"))
      header_field("Affinity", ENV.fetch("TERMISU_BENCH_AFFINITY", "externally unspecified"))
      header_field("Environment", ENV.fetch("TERMISU_BENCH_ENVIRONMENT", "externally unspecified"))
      header_field("Samples", config.samples.to_s)
      header_field("Batch target", "#{config.sample_time.total_milliseconds} ms")
      header_field("Time", Time.local.to_s)
      puts "#{CYAN}#{BOLD}╚#{"═" * 62}╝#{RESET}"
      puts
    end

    def render_suite_start(suite_name : String) : Nil
      puts "#{MAGENTA}Running:#{RESET} #{BOLD}#{suite_name}#{RESET}"
    end

    def render_group(group : BenchGroup) : Nil
      puts
      separator = "─" * Math.max(1, 50 - group.name.size)
      puts "#{BLUE}─── #{CYAN}#{BOLD}#{group.name}#{RESET} #{BLUE}#{separator}#{RESET}"
      puts

      fastest = group.results.max_by(&.iterations_per_second)
      group.results.each { |result| render_result(result, fastest.iterations_per_second) }
    end

    def render_result(result : BenchResult, fastest_ips : Float64) : Nil
      name = result.name.size > 30 ? result.name[0, 27] + "..." : result.name
      color = result.iterations_per_second >= fastest_ips * 0.95 ? BRIGHT_GREEN : GREEN
      comparison = if result.iterations_per_second < fastest_ips * 0.99
                     ratio = fastest_ips / result.iterations_per_second
                     "#{YELLOW}#{ratio.round(2)}× slower#{RESET}"
                   else
                     "#{BRIGHT_GREEN}#{BOLD}fastest#{RESET}"
                   end

      puts "  #{WHITE}#{name.ljust(31)}#{RESET} " +
           "#{color}#{BOLD}#{format_ips(result.iterations_per_second).rjust(12)}#{RESET} " +
           "(#{format_time(result.mean_time).rjust(10)}) " +
           "±#{result.std_dev_percent.round(2)}% " +
           "#{format_bytes(result.bytes_per_op)} B/op #{comparison}"

      unless result.metrics == BenchMetrics.empty
        puts "    totals: #{format_metrics(result.metrics)}"
      end

      result.samples.each_with_index do |sample, index|
        puts "    raw[#{(index + 1).to_s.rjust(2, '0')}]: " +
             "iterations=#{sample.iterations} " +
             "elapsed_ns=#{sample.elapsed.total_nanoseconds.to_i64} " +
             "ips=#{sample.iterations_per_second.round(3)} " +
             "allocated_bytes=#{sample.allocated_bytes} " +
             format_metrics(sample.metrics)
      end
    end

    def render_suite_complete(suite : BenchSuite) : Nil
      puts
      total_benchmarks = suite.groups.sum(&.results.size)
      msg = "#{BRIGHT_GREEN}#{BOLD}✓ #{suite.name} Complete#{RESET}"
      puts "#{msg} - #{suite.groups.size} groups, #{total_benchmarks} benchmarks"
    end

    def render_gc_stats : Nil
      puts
      puts "#{CYAN}#{BOLD}GC Statistics:#{RESET}"
      stats = GC.stats
      puts "  Heap size:       #{GREEN}#{stats.heap_size / 1024} KB#{RESET}"
      puts "  Free bytes:      #{GREEN}#{stats.free_bytes / 1024} KB#{RESET}"
      puts "  Total allocated: #{GREEN}#{stats.total_bytes} B#{RESET}"
    end

    def render_summary(suites : Array(BenchSuite)) : Nil
      total_groups = suites.sum(&.groups.size)
      total_benchmarks = suites.sum { |suite| suite.groups.sum(&.results.size) }

      puts
      puts "#{CYAN}#{BOLD}╔#{"═" * 40}╗#{RESET}"
      puts "#{CYAN}#{BOLD}║#{RESET}     BENCHMARK SUMMARY                  #{CYAN}#{BOLD}║#{RESET}"
      puts "#{CYAN}#{BOLD}╠#{"═" * 40}╣#{RESET}"
      summary_field("Suites", suites.size)
      summary_field("Groups", total_groups)
      summary_field("Benchmarks", total_benchmarks)
      puts "#{CYAN}#{BOLD}╚#{"═" * 40}╝#{RESET}"
    end

    private def header_field(name : String, value : String) : Nil
      text = "#{name}:".ljust(12) + value
      text = text[0, 60] if text.size > 60
      puts "#{CYAN}║#{RESET} #{text.ljust(61)}#{CYAN}║#{RESET}"
    end

    private def summary_field(name : String, value) : Nil
      value_string = value.to_s.ljust(26)
      puts "#{CYAN}║#{RESET}  #{name.ljust(11)}#{GREEN}#{value_string}#{RESET}#{CYAN}║#{RESET}"
    end

    private def format_ips(ips : Float64) : String
      case ips
      when .>= 1_000_000_000
        "#{(ips / 1_000_000_000).round(2)}B"
      when .>= 1_000_000
        "#{(ips / 1_000_000).round(2)}M"
      when .>= 1_000
        "#{(ips / 1_000).round(2)}K"
      else
        ips.round(2).to_s
      end
    end

    private def format_time(span : Time::Span) : String
      nanos = span.total_nanoseconds
      case nanos
      when .>= 1_000_000_000
        "#{(nanos / 1_000_000_000).round(2)}s"
      when .>= 1_000_000
        "#{(nanos / 1_000_000).round(2)}ms"
      when .>= 1_000
        "#{(nanos / 1_000).round(2)}µs"
      else
        "#{nanos.round(2)}ns"
      end
    end

    private def format_bytes(bytes : Float64) : String
      bytes == bytes.round ? bytes.round.to_i64.to_s : bytes.round(2).to_s
    end

    private def format_metrics(metrics : BenchMetrics) : String
      "mutations=#{metrics.mutations} " +
        "emitted_bytes=#{metrics.emitted_bytes} " +
        "string_writes=#{metrics.string_writes} " +
        "byte_writes=#{metrics.byte_writes} " +
        "callbacks=#{metrics.callback_calls} " +
        "flushes=#{metrics.flushes}"
    end
  end

  BUILD_MODE = {% if flag?(:release) %} "release" {% else %} "debug" {% end %}

  def self.run : Nil
    config = BenchConfig.from_env
    renderer = TextRenderer.new
    renderer.render_header("TERMISU BENCHMARK SUITE", config)

    # Deliberately serial: registration, execution, and rendering have one
    # stable order, and each suite factory is called exactly once.
    suites = [] of BenchSuite
    run_suite(suites, renderer, "Harness") { AllocationControlSuite.run(config) }
    run_suite(suites, renderer, "Buffer") { BufferSuite.run(config) }
    run_suite(suites, renderer, "Color") { ColorSuite.run(config) }
    run_suite(suites, renderer, "Parser") { ParserSuite.run(config) }

    renderer.render_gc_stats
    renderer.render_summary(suites)
  end

  private def self.run_suite(
    suites : Array(BenchSuite),
    renderer : TextRenderer,
    name : String,
    &block : -> Array(BenchGroup)
  ) : Nil
    renderer.render_suite_start(name)
    suite = BenchSuite.new(name, block.call)
    suites << suite
    suite.groups.each { |group| renderer.render_group(group) }
    renderer.render_suite_complete(suite)
  end
end

Termisu::Bench.run
