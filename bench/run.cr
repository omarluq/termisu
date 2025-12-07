require "./bench_runner"
require "./suites/buffer_suite"
require "./suites/color_suite"
require "./suites/parser_suite"

# Benchmark runner using Crystal fibers
#
# Usage: crystal run bench/run.cr
#        crystal run bench/run.cr --release

module Termisu::Bench
  # ANSI color codes for styled output
  module ANSIColors
    RESET        = "\e[0m"
    BOLD         = "\e[1m"
    RED          = "\e[31m"
    GREEN        = "\e[32m"
    YELLOW       = "\e[33m"
    BLUE         = "\e[34m"
    MAGENTA      = "\e[35m"
    CYAN         = "\e[36m"
    WHITE        = "\e[37m"
    BRIGHT_GREEN = "\e[92m"
  end

  # Text-based benchmark renderer with ANSI colors
  class TextRenderer
    include ANSIColors

    def render_header(title : String)
      puts "#{CYAN}#{BOLD}╔#{"═" * 62}╗#{RESET}"
      puts "#{CYAN}#{BOLD}║#{title.center(62)}║#{RESET}"
      puts "#{CYAN}#{BOLD}╠#{"═" * 62}╣#{RESET}"
      puts "#{CYAN}║#{RESET} Crystal: #{Crystal::VERSION.ljust(52)}#{CYAN}║#{RESET}"
      puts "#{CYAN}║#{RESET} LLVM:    #{Crystal::LLVM_VERSION.ljust(52)}#{CYAN}║#{RESET}"
      puts "#{CYAN}║#{RESET} Time:    #{Time.local.to_s.ljust(52)}#{CYAN}║#{RESET}"
      puts "#{CYAN}#{BOLD}╚#{"═" * 62}╝#{RESET}"
      puts
    end

    def render_suite_start(suite_name : String)
      puts "#{MAGENTA}Running:#{RESET} #{BOLD}#{suite_name}#{RESET}"
    end

    def render_group(group : BenchGroup)
      puts
      separator = "─" * (50 - group.name.size)
      puts "#{BLUE}─── #{CYAN}#{BOLD}#{group.name}#{RESET} #{BLUE}#{separator}#{RESET}"
      puts

      # Find fastest for comparison
      fastest = group.results.max_by(&.iterations_per_second)

      group.results.each do |result|
        render_result(result, fastest.iterations_per_second)
      end
    end

    def render_result(result : BenchResult, fastest_ips : Float64)
      name = result.name.size > 25 ? result.name[0, 22] + "..." : result.name
      ips_str = format_ips(result.iterations_per_second)
      time_str = format_time(result.mean_time)

      color = result.iterations_per_second >= fastest_ips * 0.95 ? BRIGHT_GREEN : GREEN

      comparison = if result.iterations_per_second < fastest_ips * 0.99
                     ratio = fastest_ips / result.iterations_per_second
                     "#{YELLOW}#{ratio.round(2)}× slower#{RESET}"
                   else
                     "#{BRIGHT_GREEN}#{BOLD}fastest#{RESET}"
                   end

      line = "  #{WHITE}#{name.ljust(26)}#{RESET} "
      line += "#{color}#{BOLD}#{ips_str.rjust(12)}#{RESET} "
      line += "(#{time_str.rjust(10)}) #{comparison}"
      puts line
    end

    def render_suite_complete(suite : BenchSuite)
      puts
      total_benchmarks = suite.groups.sum(&.results.size)
      msg = "#{BRIGHT_GREEN}#{BOLD}✓ #{suite.name} Complete#{RESET}"
      puts "#{msg} - #{suite.groups.size} groups, #{total_benchmarks} benchmarks"
    end

    def render_gc_stats
      puts
      puts "#{CYAN}#{BOLD}GC Statistics:#{RESET}"
      stats = GC.stats
      puts "  Heap size:  #{GREEN}#{stats.heap_size / 1024} KB#{RESET}"
      puts "  Free bytes: #{GREEN}#{stats.free_bytes / 1024} KB#{RESET}"
    end

    def render_summary(suites : Array(BenchSuite))
      total_groups = suites.sum(&.groups.size)
      total_benchmarks = suites.sum { |suite| suite.groups.sum(&.results.size) }

      puts
      puts "#{CYAN}#{BOLD}╔#{"═" * 40}╗#{RESET}"
      puts "#{CYAN}#{BOLD}║#{RESET}     BENCHMARK SUMMARY                  #{CYAN}#{BOLD}║#{RESET}"
      puts "#{CYAN}#{BOLD}╠#{"═" * 40}╣#{RESET}"
      suites_str = suites.size.to_s.ljust(26)
      puts "#{CYAN}║#{RESET}  Suites:     #{GREEN}#{suites_str}#{RESET}#{CYAN}║#{RESET}"
      groups_str = total_groups.to_s.ljust(26)
      puts "#{CYAN}║#{RESET}  Groups:     #{GREEN}#{groups_str}#{RESET}#{CYAN}║#{RESET}"
      benchmarks_str = total_benchmarks.to_s.ljust(26)
      puts "#{CYAN}║#{RESET}  Benchmarks: #{GREEN}#{benchmarks_str}#{RESET}#{CYAN}║#{RESET}"
      puts "#{CYAN}#{BOLD}╚#{"═" * 40}╝#{RESET}"
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
        "#{ips.round(2)}"
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
  end

  def self.run
    renderer = TextRenderer.new

    renderer.render_header("TERMISU BENCHMARK SUITE")

    # Channel for collecting results from concurrent suites
    channel = Channel(NamedTuple(name: String, groups: Array(BenchGroup))).new

    # Number of suites to run
    suite_count = 3

    # Spawn all benchmark suites concurrently using Crystal fibers
    spawn(name: "buffer_suite") do
      groups = BufferSuite.run
      channel.send({name: "Buffer", groups: groups})
    end

    spawn(name: "color_suite") do
      groups = ColorSuite.run
      channel.send({name: "Color", groups: groups})
    end

    spawn(name: "parser_suite") do
      groups = ParserSuite.run
      channel.send({name: "Parser", groups: groups})
    end

    # Collect results as they complete
    suites = [] of BenchSuite
    completed = 0

    suite_count.times do
      result = channel.receive
      completed += 1

      suite = BenchSuite.new(result[:name], result[:groups])
      suites << suite

      # Update progress
      renderer.render_suite_start(result[:name])

      # Render the completed suite's groups
      result[:groups].each do |group|
        renderer.render_group(group)
      end

      renderer.render_suite_complete(suite)
    end

    # Final stats
    renderer.render_gc_stats
    renderer.render_summary(suites)
  end
end

Termisu::Bench.run
