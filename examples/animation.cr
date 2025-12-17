require "../src/termisu"

# Optimized animation demo with runtime timer switching.
#
# Controls:
#   T     - Toggle between Timer (sleep) and SystemTimer (kernel)
#   SPACE - Pause/resume animation
#   +/-   - Increase/decrease ball speed
#   Q/Esc - Quit
#
# Usage:
#   crystal run examples/animation.cr           # Start with sleep timer
#   crystal run examples/animation.cr --system  # Start with system timer

class AnimationDemo
  FPS_PRESETS = [30, 60, 90, 120, 144]

  @termisu : Termisu
  @width : Int32
  @height : Int32
  @using_system_timer : Bool

  # Ball state
  @ball_x : Int32
  @ball_y : Int32
  @vel_x : Int32
  @vel_y : Int32
  @speed : Int32
  @frame : UInt64
  @paused : Bool

  # Timer settings
  @target_fps : Int32
  @fps_index : Int32

  # Recording
  @recording : Bool
  @record_file : File?

  def initialize(use_system_timer : Bool)
    @termisu = Termisu.new
    @width, @height = @termisu.size

    @using_system_timer = use_system_timer

    # Ball state
    @ball_x = @width // 2
    @ball_y = @height // 2
    @vel_x = 1
    @vel_y = 1
    @speed = 1
    @frame = 0_u64
    @paused = false

    # Timer settings (start at 60 FPS)
    @fps_index = 1
    @target_fps = FPS_PRESETS[@fps_index]

    # Recording
    @recording = false
    @record_file = nil

    # Start initial timer
    enable_timer(@using_system_timer)
  end

  private def interval : Time::Span
    (1000.0 / @target_fps).milliseconds
  end

  private def slow_threshold : Float64
    # Slow = 25% over target interval
    (1000.0 / @target_fps) * 1.25
  end

  def run
    @termisu.each_event do |event|
      case event
      when Termisu::Event::Key
        handle_key(event)
      when Termisu::Event::Resize
        @width, @height = event.width, event.height
        @termisu.sync
      when Termisu::Event::Tick
        handle_tick(event)
      end
    end
  rescue ex
    # Ensure cleanup on error
    STDERR.puts "Error: #{ex.message}"
  ensure
    stop_recording if @recording
    @termisu.close
  end

  private def handle_key(event : Termisu::Event::Key)
    key = event.key
    case
    when key.escape?, key.lower_q?
      raise StopIteration.new
    when key.space?
      @paused = !@paused
    when key.lower_t?
      switch_timer
    when key.plus?, key.equals?
      @speed = (@speed + 1).clamp(1, 5)
    when key.minus?
      @speed = (@speed - 1).clamp(1, 5)
    when key.up?, key.right?, key.right_bracket?
      change_fps(1)
    when key.down?, key.left?, key.left_bracket?
      change_fps(-1)
    when key.lower_r?
      toggle_recording
    end
  end

  private def change_fps(delta : Int32)
    new_index = (@fps_index + delta).clamp(0, FPS_PRESETS.size - 1)
    return if new_index == @fps_index

    @fps_index = new_index
    @target_fps = FPS_PRESETS[@fps_index]

    # Restart timer with new interval
    disable_timer
    enable_timer(@using_system_timer)
  end

  private def handle_tick(event : Termisu::Event::Tick)
    @frame += 1

    # Calculate current FPS
    delta_ms = event.delta.total_milliseconds
    current_fps = 1000.0 / delta_ms

    # Detect issues (slow = more than 25% over target interval)
    slow_frame = delta_ms > slow_threshold
    missed = event.missed_ticks

    # Record sample if recording is active
    record_sample(@frame, delta_ms, current_fps, missed, slow_frame)

    @termisu.clear

    # Update ball position (if not paused)
    unless @paused
      @speed.times do
        @ball_x += @vel_x
        @ball_y += @vel_y

        # Bounce off walls
        if @ball_x <= 0 || @ball_x >= @width - 1
          @vel_x = -@vel_x
          @ball_x = @ball_x.clamp(0, @width - 1)
        end
        if @ball_y <= 1 || @ball_y >= @height - 3
          @vel_y = -@vel_y
          @ball_y = @ball_y.clamp(1, @height - 3)
        end
      end
    end

    render_frame(current_fps, delta_ms, slow_frame, missed)
    @termisu.render
  end

  private def render_frame(fps : Float64, delta : Float64, slow : Bool, missed : UInt64)
    # Ball color based on state
    ball_color = if missed > 0
                   Termisu::Color.yellow
                 elsif slow
                   Termisu::Color.red
                 else
                   Termisu::Color.cyan
                 end
    @termisu.set_cell(@ball_x, @ball_y, '●', fg: ball_color, attr: Termisu::Attribute::Bold)

    # Header: Timer type
    timer_name = @using_system_timer ? "SystemTimer (kernel)" : "Timer (sleep-based)"
    timer_color = @using_system_timer ? Termisu::Color.green : Termisu::Color.magenta
    draw_text(0, 0, timer_name, fg: timer_color, attr: Termisu::Attribute::Bold)

    # Stats line 1: Current performance
    warn = slow ? " SLOW" : ""
    missed_str = missed > 0 ? " MISSED:#{missed}" : ""
    pause_str = @paused ? " PAUSED" : ""
    expected_ms = (1000.0 / @target_fps).round(1)
    line1 = "Target: #{@target_fps}fps (#{expected_ms}ms) | Actual: #{fps.round(0)}fps (#{delta.round(1)}ms)#{warn}#{missed_str}#{pause_str}"
    draw_text(0, @height - 2, line1, fg: Termisu::Color.ansi256(250))

    # Stats line 2: Controls + recording status
    rec_str = @recording ? " [REC]" : ""
    line2 = "T=timer | ←→=FPS | SPACE=pause | +/-=speed(#{@speed}) | R=record#{rec_str} | Q=quit"
    draw_text(0, @height - 1, line2, fg: Termisu::Color.ansi256(245))
  end

  private def draw_text(x : Int32, y : Int32, text : String, fg : Termisu::Color = Termisu::Color.white, attr : Termisu::Attribute = Termisu::Attribute::None)
    text.each_char_with_index do |char, idx|
      break if x + idx >= @width
      @termisu.set_cell(x + idx, y, char, fg: fg, attr: attr)
    end
  end

  private def switch_timer
    # Disable current timer
    disable_timer

    # Toggle mode
    @using_system_timer = !@using_system_timer

    # Enable new timer
    enable_timer(@using_system_timer)
  end

  private def enable_timer(use_system : Bool)
    int = interval
    if use_system
      @termisu.enable_system_timer(int)
    else
      @termisu.enable_timer(int)
    end
  end

  private def disable_timer
    @termisu.disable_timer
  end

  private def toggle_recording
    if @recording
      stop_recording
    else
      start_recording
    end
  end

  private def start_recording
    timestamp = Time.local.to_s("%Y%m%d_%H%M%S")
    filename = "animation_recording_#{timestamp}.csv"
    @record_file = File.new(filename, "w")
    @record_file.try do |file|
      file.puts "frame,delta_ms,actual_fps,target_fps,timer_type,missed,slow"
    end
    @recording = true
  end

  private def stop_recording
    @record_file.try(&.close)
    @record_file = nil
    @recording = false
  end

  private def record_sample(frame : UInt64, delta_ms : Float64, fps : Float64, missed : UInt64, slow : Bool)
    return unless @recording
    @record_file.try do |file|
      timer_type = @using_system_timer ? "system" : "sleep"
      file.puts "#{frame},#{delta_ms.round(3)},#{fps.round(1)},#{@target_fps},#{timer_type},#{missed},#{slow}"
    end
  end
end

# Custom exception for clean exit
class StopIteration < Exception
end

# Entry point
use_system = ARGV.includes?("--system")
demo = AnimationDemo.new(use_system)

begin
  demo.run
rescue StopIteration
  # Clean exit
end
