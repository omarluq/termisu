# Benchmark Suite Improvement Plan

## Summary

Analysis of [Crystal Forum Post](https://forum.crystal-lang.org/t/how-to-use-benchmark-correctly/6008) reveals critical issues with current benchmark implementation.

## Current Issues

### 1. Compiler Optimization Vulnerability (CRITICAL)

**Problem**: Crystal compiler eliminates operations with no side effects.

```crystal
# CURRENT (INVALID) - compiler optimizes away
capture.report("Color.default") { Color.default }
capture.report("color ==") { color1 == color2 }
```

**Affected Files**:
| File | Affected Benchmarks |
|------|---------------------|
| `color_suite.cr` | `Color.default`, `Color.black`, `Color.ansi256`, `Color.rgb`, all conversions, equality checks |
| `buffer_suite.cr` | `hide_cursor`, `show_cursor` (void returns okay) |
| `parser_suite.cr` | `Parser.new`, `parse`, `parse?` |

### 2. Hardcoded Constants (HIGH)

**Problem**: Compile-time constant evaluation bypasses runtime measurement.

```crystal
# CURRENT - may be evaluated at compile time
Color.ansi256(42)
Color.rgb(128, 64, 255)
```

### 3. Insufficient Warmup & Measurement (HIGH)

| Metric | Current | Best Practice |
|--------|---------|---------------|
| Warmup | 100 iterations | 2s (time-based) |
| Measurement | 100ms | 2-5s |
| Samples | 1 | 3-5 |
| Std Dev | Always 0.0 | Calculated |

### 4. No Memory Tracking (MEDIUM)

`bytes_per_op` always `0_i64` - no allocation tracking.

---

## Implementation Plan

### Phase 1: Fix Compiler Optimization Issues

**Objective**: Ensure all benchmarks produce valid measurements.

**Pattern**:
```crystal
# Before
capture.report("Color.default") { Color.default }

# After - capture return value
y = Color.default
capture.report("Color.default") { y = Color.default }
```

**Changes Required**:

#### `color_suite.cr`
```crystal
# Creation benchmarks
y = Color.default
capture.report("Color.default") { y = Color.default }
capture.report("Color.black") { y = Color.black }

# Use runtime values
idx = rand(256).to_u8
capture.report("Color.ansi256(index)") { y = Color.ansi256(idx) }

r, g, b = rand(256).to_u8, rand(256).to_u8, rand(256).to_u8
capture.report("Color.rgb(r,g,b)") { y = Color.rgb(r, g, b) }

# Conversion benchmarks
result = 0_u8
capture.report("rgb_to_ansi256") { result = Color::Conversions.rgb_to_ansi256(r, g, b) }

tuple = {0_u8, 0_u8, 0_u8}
capture.report("ansi256_to_rgb") { tuple = Color::Conversions.ansi256_to_rgb(idx) }

# Equality benchmarks
eq_result = false
capture.report("color == (equal)") { eq_result = color1 == color2 }
```

#### `parser_suite.cr`
```crystal
parser = Terminfo::Parser.new(mock_data)
capture.report("Parser.new") { parser = Terminfo::Parser.new(mock_data) }

caps = {} of String => String?
capture.report("parse 1 cap") { caps = parser.parse(["clear"]) }
```

### Phase 2: Upgrade Measurement Engine

**Objective**: Match `Benchmark.ips` statistical rigor.

**Replace `BenchCapture.report`**:

```crystal
class BenchCapture
  WARMUP_DURATION = 500.milliseconds
  SAMPLE_DURATION = 500.milliseconds
  SAMPLE_COUNT = 5

  def report(name : String, &block)
    # Time-based warmup
    warmup_start = Time.instant
    while (Time.instant - warmup_start) < WARMUP_DURATION
      block.call
    end

    # Multi-sample measurement
    samples = [] of Float64
    SAMPLE_COUNT.times do
      iterations = 0
      gc_before = GC.stats.total_bytes

      start = Time.instant
      while (Time.instant - start) < SAMPLE_DURATION
        block.call
        iterations += 1
      end
      elapsed = Time.instant - start

      gc_after = GC.stats.total_bytes
      samples << iterations / elapsed.total_seconds
      @last_bytes_delta = (gc_after - gc_before) / iterations
    end

    # Statistical analysis
    mean_ips = samples.sum / samples.size
    variance = samples.map { |s| (s - mean_ips) ** 2 }.sum / samples.size
    std_dev = Math.sqrt(variance)
    std_dev_percent = (std_dev / mean_ips) * 100.0
    mean_time = Time::Instant.new(nanoseconds: (1_000_000_000 / mean_ips).to_i64)

    @results << BenchResult.new(
      name: name,
      iterations_per_second: mean_ips,
      mean_time: mean_time,
      std_dev_percent: std_dev_percent,
      bytes_per_op: @last_bytes_delta
    )
  end
end
```

### Phase 3: Add Memory Tracking

**Objective**: Track allocation overhead per operation.

```crystal
# Track GC allocation delta
gc_before = GC.stats.total_bytes
# ... run benchmark ...
gc_after = GC.stats.total_bytes
bytes_per_op = (gc_after - gc_before) / iterations
```

**Renderer Update**:
```crystal
def render_result(result : BenchResult, fastest_ips : Float64)
  # ... existing code ...

  # Add allocation info if significant
  if result.bytes_per_op > 0
    line += " #{YELLOW}#{result.bytes_per_op}B/op#{RESET}"
  end
end
```

### Phase 4: Statistical Improvements

**Add to output**:
- Standard deviation percentage (already in struct)
- Confidence indicator: `(+/- X%)`

```crystal
def render_result(result : BenchResult, fastest_ips : Float64)
  # ... existing code ...

  # Add variance indicator
  variance_color = result.std_dev_percent < 5.0 ? GREEN : YELLOW
  line += " #{variance_color}(+/-#{result.std_dev_percent.round(1)}%)#{RESET}"
end
```

---

## Timeline

| Phase | Priority | Effort | Impact |
|-------|----------|--------|--------|
| 1. Fix optimization | CRITICAL | 2h | Measurements valid |
| 2. Upgrade engine | HIGH | 3h | Statistical rigor |
| 3. Memory tracking | MEDIUM | 1h | Allocation insights |
| 4. Stats display | LOW | 1h | Better reporting |

**Total**: ~7 hours

## Validation

After implementation, verify with:

```bash
# Compare before/after
bin/hace bench > before.txt
# ... apply changes ...
bin/hace bench > after.txt

# Look for:
# 1. Reasonable IPS values (not billions for simple ops)
# 2. Non-zero std_dev values
# 3. Memory tracking showing allocations
```

## References

- [Crystal Forum: How to use Benchmark correctly](https://forum.crystal-lang.org/t/how-to-use-benchmark-correctly/6008)
- Crystal stdlib `Benchmark.ips` implementation
