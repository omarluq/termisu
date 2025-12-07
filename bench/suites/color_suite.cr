require "../bench_runner"

module Termisu::Bench
  module ColorSuite
    extend self

    def run : Array(BenchGroup)
      groups = [] of BenchGroup

      groups << run_creation_benchmarks
      groups << run_conversion_benchmarks
      groups << run_palette_benchmarks
      groups << run_equality_benchmarks
      groups << run_escape_sequence_benchmarks

      groups
    end

    private def run_creation_benchmarks : BenchGroup
      capture = BenchCapture.new

      capture.report("Color.default") { Color.default }
      capture.report("Color.black") { Color.black }
      capture.report("Color.ansi256(index)") { Color.ansi256(42) }
      capture.report("Color.rgb(r,g,b)") { Color.rgb(128, 64, 255) }

      BenchGroup.new("Color Creation", capture.results)
    end

    private def run_conversion_benchmarks : BenchGroup
      capture = BenchCapture.new

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

    private def run_palette_benchmarks : BenchGroup
      capture = BenchCapture.new

      capture.report("basic_color(:red)") do
        Color::Palette.basic_color(:red)
      end

      capture.report("grayscale_color(12)") do
        Color::Palette.grayscale_color(12)
      end

      capture.report("grayscale range check") do
        idx = rand(256).to_u8
        idx >= 232 && idx <= 255
      end

      BenchGroup.new("Palette Lookups", capture.results)
    end

    private def run_equality_benchmarks : BenchGroup
      color1 = Color.rgb(100_u8, 150_u8, 200_u8)
      color2 = Color.rgb(100_u8, 150_u8, 200_u8)
      color3 = Color.rgb(200_u8, 150_u8, 100_u8)

      capture = BenchCapture.new

      capture.report("color == (equal)") { color1 == color2 }
      capture.report("color == (not equal)") { color1 == color3 }

      BenchGroup.new("Color Equality", capture.results)
    end

    private def run_escape_sequence_benchmarks : BenchGroup
      capture = BenchCapture.new

      capture.report("build fg sequence") do
        "\e[38;5;#{rand(256)}m"
      end

      capture.report("build rgb sequence") do
        "\e[38;2;#{rand(256)};#{rand(256)};#{rand(256)}m"
      end

      capture.report("build combined") do
        "\e[38;5;#{rand(256)};48;5;#{rand(256)}m"
      end

      BenchGroup.new("Escape Sequence Building", capture.results)
    end
  end
end
