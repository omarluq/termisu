require "../bench_runner"

module Termisu::Bench
  # Renderer sink that follows the same Bytes path as Terminal and records I/O
  # independently from allocations measured by the runner.
  class NullRenderer < Renderer
    getter emitted_bytes = 0_u64
    getter string_writes = 0_u64
    getter byte_writes = 0_u64
    getter callback_calls = 0_u64
    getter flushes = 0_u64

    @expected_byte : UInt8? = nil

    def write(data : String, columns_advanced = 0) : Nil
      validate_payload(data.to_slice)
      @string_writes += 1
      @emitted_bytes += data.bytesize.to_u64
    end

    def write(data : Bytes, columns_advanced = 0) : Nil
      validate_payload(data)
      @byte_writes += 1
      @emitted_bytes += data.size.to_u64
    end

    def move_cursor(x : Int32, y : Int32) : Nil
      count_callback
    end

    def foreground=(color : Color) : Nil
      count_callback
    end

    def background=(color : Color) : Nil
      count_callback
    end

    def flush : Nil
      @flushes += 1
    end

    def reset_attributes : Nil
      count_callback
    end

    def enable_bold : Nil
      count_callback
    end

    def enable_underline : Nil
      count_callback
    end

    def enable_blink : Nil
      count_callback
    end

    def enable_reverse : Nil
      count_callback
    end

    def enable_dim : Nil
      count_callback
    end

    def enable_cursive : Nil
      count_callback
    end

    def enable_hidden : Nil
      count_callback
    end

    def enable_strikethrough : Nil
      count_callback
    end

    def show_cursor : Nil
      count_callback
    end

    def hide_cursor : Nil
      count_callback
    end

    def size : {Int32, Int32}
      {80, 24}
    end

    def close; end

    def expect_uniform_payload(byte : UInt8?) : Nil
      @expected_byte = byte
    end

    def reset_metrics : Nil
      @emitted_bytes = 0_u64
      @string_writes = 0_u64
      @byte_writes = 0_u64
      @callback_calls = 0_u64
      @flushes = 0_u64
    end

    def metrics(mutations = 0_u64) : BenchMetrics
      BenchMetrics.new(
        mutations,
        @emitted_bytes,
        @string_writes,
        @byte_writes,
        @callback_calls,
        @flushes
      )
    end

    private def validate_payload(data : Bytes) : Nil
      return unless expected = @expected_byte
      raise "renderer emitted an unexpected payload" unless data.all? { |byte| byte == expected }
    end

    private def count_callback : Nil
      @callback_calls += 1
    end
  end

  # Counts only transitions proved from the fixture's observable state. It is
  # reset outside each measured sample; failed state checks abort the run.
  class MutationProbe
    getter count = 0_u64

    def reset : Nil
      @count = 0_u64
    end

    def observe_cell_change(
      buffer : Buffer,
      x : Int32,
      y : Int32,
      before : Cell,
      expected : Cell,
    ) : UInt64
      after = cell_at(buffer, x, y)
      raise "cell mutation did not produce the expected state" unless before != after && after == expected
      mark
    end

    def observe_frame_change(
      buffer : Buffer,
      before_first : Cell,
      before_last : Cell,
      expected : Cell,
      last_x : Int32,
      last_y : Int32,
    ) : UInt64
      after_first = cell_at(buffer, 0, 0)
      after_last = cell_at(buffer, last_x, last_y)
      changed = before_first != after_first && before_last != after_last
      raise "frame mutation did not produce the expected boundary cells" unless changed &&
                                                                                after_first == expected &&
                                                                                after_last == expected
      mark
    end

    def observe_fill_and_clear(
      buffer : Buffer,
      before_first : Cell,
      before_last : Cell,
      filled_first : Cell,
      filled_last : Cell,
      expected_filled : Cell,
    ) : UInt64
      after_first = cell_at(buffer, 0, 0)
      after_last = cell_at(buffer, buffer.width - 1, buffer.height - 1)
      valid = before_first.default_state? && before_last.default_state? &&
              filled_first == expected_filled && filled_last == expected_filled &&
              after_first.default_state? && after_last.default_state?
      raise "refill + clear did not complete both state transitions" unless valid
      mark
    end

    def observe_resize(
      buffer : Buffer,
      before_width : Int32,
      before_height : Int32,
      expected_width : Int32,
      expected_height : Int32,
    ) : UInt64
      changed = before_width != buffer.width || before_height != buffer.height
      expected = buffer.width == expected_width && buffer.height == expected_height
      raise "resize did not produce the expected dimensions" unless changed && expected
      mark
    end

    def metrics(renderer : NullRenderer? = nil) : BenchMetrics
      renderer ? renderer.metrics(@count) : BenchMetrics.new(@count, 0_u64, 0_u64, 0_u64, 0_u64, 0_u64)
    end

    private def cell_at(buffer : Buffer, x : Int32, y : Int32) : Cell
      buffer.get_cell(x, y) || raise "benchmark cell coordinates are out of bounds"
    end

    private def mark : UInt64
      @count += 1
    end
  end

  module BufferSuite
    extend self

    def run(config : BenchConfig = BenchConfig.from_env) : Array(BenchGroup)
      groups = [] of BenchGroup

      groups << run_cell_operations(config)
      groups << run_clear_operations(config)
      groups << run_fill_operations(config)
      groups << run_render_operations(config)
      groups << run_sync_operations(config)
      groups << run_resize_operations(config)

      groups
    end

    private def run_cell_operations(config : BenchConfig) : BenchGroup
      capture = BenchCapture.new(config)

      add_cell_job(capture, "set_cell (small)", Buffer.new(80, 24), 40, 12)
      add_cell_job(capture, "set_cell (large)", Buffer.new(200, 60), 100, 30)

      buffer = Buffer.new(80, 24)
      probe = MutationProbe.new
      alternate = false
      expected_x = Cell.new("X", fg: Color.green, bg: Color.black, attr: Attribute::Bold)
      expected_y = Cell.new("Y", fg: Color.cyan, bg: Color.black, attr: Attribute::Underline)
      capture.report(
        "set_cell with attrs",
        before_sample: -> { probe.reset },
        sample_metrics: -> { probe.metrics },
        mutations_per_iteration: true
      ) do
        alternate = !alternate
        before = cell_at(buffer, 40, 12)
        expected = alternate ? expected_x : expected_y
        buffer.set_cell(40, 12, expected.grapheme, expected.fg, expected.bg, expected.attr)
        probe.observe_cell_change(buffer, 40, 12, before, expected)
      end

      BenchGroup.new("Cell Set Operations", capture.results)
    end

    private def add_cell_job(capture : BenchCapture, name : String, buffer : Buffer, x : Int32, y : Int32) : Nil
      probe = MutationProbe.new
      alternate = false
      expected_a = Cell.new("A")
      expected_b = Cell.new("B")
      capture.report(
        name,
        before_sample: -> { probe.reset },
        sample_metrics: -> { probe.metrics },
        mutations_per_iteration: true
      ) do
        alternate = !alternate
        before = cell_at(buffer, x, y)
        expected = alternate ? expected_a : expected_b
        buffer.set_cell(x, y, expected.grapheme)
        probe.observe_cell_change(buffer, x, y, before, expected)
      end
    end

    private def run_clear_operations(config : BenchConfig) : BenchGroup
      capture = BenchCapture.new(config)

      add_clear_job(capture, "refill + clear (small)", Buffer.new(80, 24))
      add_clear_job(capture, "refill + clear (medium)", Buffer.new(120, 40))
      add_clear_job(capture, "refill + clear (large)", Buffer.new(200, 60))

      BenchGroup.new("Buffer Clear", capture.results)
    end

    private def add_clear_job(capture : BenchCapture, name : String, buffer : Buffer) : Nil
      probe = MutationProbe.new
      alternate = false
      expected_a = Cell.new("A")
      expected_b = Cell.new("B")
      capture.report(
        name,
        before_sample: -> { probe.reset },
        sample_metrics: -> { probe.metrics },
        mutations_per_iteration: true
      ) do
        alternate = !alternate
        expected = alternate ? expected_a : expected_b
        before_first = cell_at(buffer, 0, 0)
        before_last = cell_at(buffer, buffer.width - 1, buffer.height - 1)
        buffer.height.times do |row|
          buffer.width.times { |column| buffer.set_cell(column, row, expected.grapheme) }
        end
        filled_first = cell_at(buffer, 0, 0)
        filled_last = cell_at(buffer, buffer.width - 1, buffer.height - 1)
        buffer.clear
        probe.observe_fill_and_clear(buffer, before_first, before_last, filled_first, filled_last, expected)
      end
    end

    private def run_fill_operations(config : BenchConfig) : BenchGroup
      capture = BenchCapture.new(config)

      add_fill_job(capture, "fill small A/B (80x24)", Buffer.new(80, 24))
      add_fill_job(capture, "fill medium A/B (120x40)", Buffer.new(120, 40))

      BenchGroup.new("Full Screen Fill", capture.results)
    end

    private def add_fill_job(capture : BenchCapture, name : String, buffer : Buffer) : Nil
      probe = MutationProbe.new
      alternate = false
      expected_a = Cell.new("A")
      expected_b = Cell.new("B")
      last_x = buffer.width - 1
      last_y = buffer.height - 1
      capture.report(
        name,
        before_sample: -> { probe.reset },
        sample_metrics: -> { probe.metrics },
        mutations_per_iteration: true
      ) do
        alternate = !alternate
        expected = alternate ? expected_a : expected_b
        before_first = cell_at(buffer, 0, 0)
        before_last = cell_at(buffer, last_x, last_y)
        buffer.height.times do |row|
          buffer.width.times { |column| buffer.set_cell(column, row, expected.grapheme) }
        end
        probe.observe_frame_change(buffer, before_first, before_last, expected, last_x, last_y)
      end
    end

    private def run_render_operations(config : BenchConfig) : BenchGroup
      capture = BenchCapture.new(config)
      renderer = NullRenderer.new

      clean = Buffer.new(80, 24)
      add_renderer_job(capture, "render_to (no changes)", renderer, emitted_bytes_per_iteration: 0_u64) do
        clean.render_to(renderer)
      end

      one_cell = Buffer.new(80, 24)
      probe = MutationProbe.new
      alternate = false
      expected_a = Cell.new("A")
      expected_b = Cell.new("B")
      add_renderer_job(capture, "render_to (1 cell A/B)", renderer, probe, emitted_bytes_per_iteration: 1_u64) do
        alternate = !alternate
        expected = alternate ? expected_a : expected_b
        renderer.expect_uniform_payload(expected.grapheme.byte_at(0))
        before = cell_at(one_cell, 40, 12)
        one_cell.set_cell(40, 12, expected.grapheme)
        probe.observe_cell_change(one_cell, 40, 12, before, expected)
        one_cell.render_to(renderer)
      end

      changed = Buffer.new(80, 24)
      probe = MutationProbe.new
      alternate = false
      expected_x = Cell.new("X")
      expected_y = Cell.new("Y")
      add_renderer_job(capture, "render_to (10% A/B)", renderer, probe, emitted_bytes_per_iteration: 192_u64) do
        alternate = !alternate
        expected = alternate ? expected_x : expected_y
        renderer.expect_uniform_payload(expected.grapheme.byte_at(0))
        before_first = cell_at(changed, 0, 0)
        before_last = cell_at(changed, 31, 2)
        192.times do |index|
          changed.set_cell(index % 80, index // 80, expected.grapheme)
        end
        probe.observe_frame_change(changed, before_first, before_last, expected, 31, 2)
        changed.render_to(renderer)
      end

      BenchGroup.new("Render Operations (Diff-Based)", capture.results)
    end

    private def add_renderer_job(
      capture : BenchCapture,
      name : String,
      renderer : NullRenderer,
      probe : MutationProbe? = nil,
      emitted_bytes_per_iteration : UInt64? = nil,
      &block
    ) : Nil
      validate_sample = ->(sample : BenchSample) {
        metrics = sample.metrics
        expected_bytes = emitted_bytes_per_iteration.try { |bytes| bytes * sample.iterations.to_u64 }
        raise "#{name}: unexpected emitted byte count" if expected_bytes && metrics.emitted_bytes != expected_bytes
        raise "#{name}: String write bypassed Bytes path" unless metrics.string_writes.zero?
        raise "#{name}: expected one flush per iteration" unless metrics.flushes == sample.iterations.to_u64
        if metrics.emitted_bytes > 0 && metrics.byte_writes.zero?
          raise "#{name}: emitted payload without a Bytes write"
        end
      }

      capture.report(
        name,
        before_sample: -> {
          renderer.reset_metrics
          probe.try(&.reset)
        },
        sample_metrics: -> { probe ? probe.metrics(renderer) : renderer.metrics },
        validate_sample: validate_sample,
        mutations_per_iteration: !probe.nil?
      ) do
        block.call
      end
    end

    private def run_sync_operations(config : BenchConfig) : BenchGroup
      capture = BenchCapture.new(config)
      renderer = NullRenderer.new
      renderer.expect_uniform_payload(' '.ord.to_u8)
      small = Buffer.new(80, 24)
      medium = Buffer.new(120, 40)
      large = Buffer.new(200, 60)

      add_renderer_job(capture, "sync (small)", renderer, emitted_bytes_per_iteration: 80_u64 * 24) do
        small.sync_to(renderer)
      end
      add_renderer_job(capture, "sync (medium)", renderer, emitted_bytes_per_iteration: 120_u64 * 40) do
        medium.sync_to(renderer)
      end
      add_renderer_job(capture, "sync (large)", renderer, emitted_bytes_per_iteration: 200_u64 * 60) do
        large.sync_to(renderer)
      end

      BenchGroup.new("Sync Operations (Full Redraw)", capture.results)
    end

    private def cell_at(buffer : Buffer, x : Int32, y : Int32) : Cell
      buffer.get_cell(x, y) || raise "benchmark cell coordinates are out of bounds"
    end

    private def run_resize_operations(config : BenchConfig) : BenchGroup
      capture = BenchCapture.new(config)
      buffer = Buffer.new(80, 24)
      probe = MutationProbe.new
      large = false

      capture.report(
        "resize alternating 80x24 / 120x40",
        before_sample: -> { probe.reset },
        sample_metrics: -> { probe.metrics },
        mutations_per_iteration: true
      ) do
        before_width = buffer.width
        before_height = buffer.height
        large = !large
        expected_width, expected_height = large ? {120, 40} : {80, 24}
        buffer.resize(expected_width, expected_height)
        probe.observe_resize(buffer, before_width, before_height, expected_width, expected_height)
      end

      probe = MutationProbe.new
      capture.report(
        "construct + resize grow",
        before_sample: -> { probe.reset },
        sample_metrics: -> { probe.metrics },
        mutations_per_iteration: true
      ) do
        fresh = Buffer.new(80, 24)
        fresh.resize(120, 40)
        probe.observe_resize(fresh, 80, 24, 120, 40)
      end

      capture.report("resize same (no-op control)") do
        fresh = Buffer.new(80, 24)
        fresh.resize(80, 24)
        raise "same-size resize changed dimensions" unless fresh.width == 80 && fresh.height == 24
      end

      BenchGroup.new("Resize Operations", capture.results)
    end
  end
end
