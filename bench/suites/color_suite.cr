require "../bench_runner"

module Termisu::Bench
  module ColorSuite
    extend self

    def run(config : BenchConfig = BenchConfig.from_env) : Array(BenchGroup)
      groups = [] of BenchGroup

      groups << run_creation_benchmarks(config)
      groups << run_conversion_benchmarks(config)
      groups << run_palette_benchmarks(config)
      groups << run_equality_benchmarks(config)
      groups << run_escape_sequence_benchmarks(config)

      groups
    end

    private def run_creation_benchmarks(config : BenchConfig) : BenchGroup
      capture = BenchCapture.new(config)

      capture.report("Color.default") { Color.default }
      capture.report("Color.black") { Color.black }
      capture.report("Color.ansi256(index)") { Color.ansi256(42) }
      capture.report("Color.rgb(r,g,b)") { Color.rgb(128, 64, 255) }

      BenchGroup.new("Color Creation", capture.results)
    end

    private def run_conversion_benchmarks(config : BenchConfig) : BenchGroup
      capture = BenchCapture.new(config)

      capture.report("rgb_to_ansi256") do
        Color::Conversions.rgb_to_ansi256(128_u8, 64_u8, 200_u8)
      end

      capture.report("ansi256_to_rgb") do
        Color::Conversions.ansi256_to_rgb(196)
      end

      capture.report("rgb_to_ansi8") do
        Color::Conversions.rgb_to_ansi8(128_u8, 64_u8, 200_u8)
      end

      BenchGroup.new("Color Conversions", capture.results)
    end

    private def run_palette_benchmarks(config : BenchConfig) : BenchGroup
      capture = BenchCapture.new(config)
      index = 0_u8

      capture.report("basic_color(:red)") do
        Color::Palette.basic_color(:red)
      end

      capture.report("grayscale_color(12)") do
        Color::Palette.grayscale_color(12)
      end

      capture.report("grayscale range check", before_sample: -> { index = 0_u8; nil }) do
        index &+= 1
        index >= 232 && index <= 255
      end

      BenchGroup.new("Palette Lookups", capture.results)
    end

    private def run_equality_benchmarks(config : BenchConfig) : BenchGroup
      color1 = Color.rgb(100_u8, 150_u8, 200_u8)
      color2 = Color.rgb(100_u8, 150_u8, 200_u8)
      color3 = Color.rgb(200_u8, 150_u8, 100_u8)

      capture = BenchCapture.new(config)

      capture.report("color == (equal)") { color1 == color2 }
      capture.report("color == (not equal)") { color1 == color3 }

      BenchGroup.new("Color Equality", capture.results)
    end

    private def run_escape_sequence_benchmarks(config : BenchConfig) : BenchGroup
      capture = BenchCapture.new(config)
      index = 0_u8
      reset_index = -> { index = 0_u8; nil }

      capture.report("build fg sequence", before_sample: reset_index) do
        index &+= 1
        "\e[38;5;#{index}m"
      end

      capture.report("build rgb sequence", before_sample: reset_index) do
        index &+= 1
        "\e[38;2;#{index};#{index &+ 1};#{index &+ 2}m"
      end

      capture.report("build combined", before_sample: reset_index) do
        index &+= 1
        "\e[38;5;#{index};48;5;#{index &+ 1}m"
      end

      BenchGroup.new("Escape Sequence Building", capture.results)
    end
  end
end
