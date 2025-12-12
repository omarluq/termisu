require "../bench_runner"

module Termisu::Bench
  # Mock renderer for benchmarking flush operations
  class NullRenderer < Renderer
    def write(data : String); end

    def move_cursor(x : Int32, y : Int32); end

    def foreground=(color : Color); end

    def background=(color : Color); end

    def flush; end

    def reset_attributes; end

    def enable_bold; end

    def enable_underline; end

    def enable_blink; end

    def enable_reverse; end

    def enable_dim; end

    def enable_cursive; end

    def enable_hidden; end

    def enable_strikethrough; end

    def write_show_cursor; end

    def write_hide_cursor; end

    def size : {Int32, Int32}
      {80, 24}
    end

    def close; end
  end

  module BufferSuite
    extend self

    def run : Array(BenchGroup)
      groups = [] of BenchGroup

      # Shared resources
      small_buffer = Buffer.new(80, 24)
      medium_buffer = Buffer.new(120, 40)
      large_buffer = Buffer.new(200, 60)
      renderer = NullRenderer.new

      groups << run_cell_operations(small_buffer, large_buffer)
      groups << run_clear_operations(small_buffer, medium_buffer, large_buffer)
      groups << run_fill_operations(small_buffer, medium_buffer)
      groups << run_render_operations(small_buffer, renderer)
      groups << run_sync_operations(small_buffer, medium_buffer, large_buffer, renderer)
      groups << run_resize_operations
      groups << run_cursor_operations(small_buffer)

      groups
    end

    private def run_cell_operations(small : Buffer, large : Buffer) : BenchGroup
      capture = BenchCapture.new

      capture.report("set_cell (small)") do
        small.set_cell(rand(80), rand(24), 'A')
      end

      capture.report("set_cell (large)") do
        large.set_cell(rand(200), rand(60), 'A')
      end

      capture.report("set_cell with attrs") do
        small.set_cell(
          rand(80), rand(24), 'X',
          fg: Color.green,
          bg: Color.black,
          attr: Attribute::Bold
        )
      end

      BenchGroup.new("Cell Set Operations", capture.results)
    end

    private def run_clear_operations(small : Buffer, medium : Buffer, large : Buffer) : BenchGroup
      capture = BenchCapture.new

      capture.report("clear (small)") { small.clear }
      capture.report("clear (medium)") { medium.clear }
      capture.report("clear (large)") { large.clear }

      BenchGroup.new("Buffer Clear", capture.results)
    end

    private def run_fill_operations(small : Buffer, medium : Buffer) : BenchGroup
      capture = BenchCapture.new

      capture.report("fill small (80x24)") do
        24.times do |row|
          80.times do |col|
            small.set_cell(col, row, '#')
          end
        end
      end

      capture.report("fill medium (120x40)") do
        40.times do |row|
          120.times do |col|
            medium.set_cell(col, row, '#')
          end
        end
      end

      BenchGroup.new("Full Screen Fill", capture.results)
    end

    private def run_render_operations(buffer : Buffer, renderer : Renderer) : BenchGroup
      capture = BenchCapture.new

      capture.report("render_to (no changes)") do
        buffer.render_to(renderer)
      end

      capture.report("render_to (1 cell changed)") do
        buffer.set_cell(40, 12, ((rand(26) + 65).to_u8).unsafe_chr)
        buffer.render_to(renderer)
      end

      capture.report("render_to (10% changed)") do
        192.times { buffer.set_cell(rand(80), rand(24), 'X') }
        buffer.render_to(renderer)
      end

      BenchGroup.new("Render Operations (Diff-Based)", capture.results)
    end

    private def run_sync_operations(small : Buffer, medium : Buffer, large : Buffer, renderer : Renderer) : BenchGroup
      capture = BenchCapture.new

      capture.report("sync (small)") { small.sync_to(renderer) }
      capture.report("sync (medium)") { medium.sync_to(renderer) }
      capture.report("sync (large)") { large.sync_to(renderer) }

      BenchGroup.new("Sync Operations (Full Redraw)", capture.results)
    end

    private def run_resize_operations : BenchGroup
      capture = BenchCapture.new

      capture.report("resize grow") do
        buf = Buffer.new(80, 24)
        buf.resize(120, 40)
      end

      capture.report("resize shrink") do
        buf = Buffer.new(120, 40)
        buf.resize(80, 24)
      end

      capture.report("resize same (no-op)") do
        buf = Buffer.new(80, 24)
        buf.resize(80, 24)
      end

      BenchGroup.new("Resize Operations", capture.results)
    end

    private def run_cursor_operations(buffer : Buffer) : BenchGroup
      capture = BenchCapture.new

      capture.report("set_cursor") { buffer.set_cursor(rand(80), rand(24)) }
      capture.report("hide_cursor") { buffer.hide_cursor }
      capture.report("show_cursor") { buffer.show_cursor }

      BenchGroup.new("Cursor Operations", capture.results)
    end
  end
end
