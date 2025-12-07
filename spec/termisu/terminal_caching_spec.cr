require "../spec_helper"

# Test-only Terminal subclass that captures writes for verification
# without requiring a real TTY connection
class CaptureTerminal < Termisu::Renderer
  property writes : Array(String) = [] of String
  property flush_count : Int32 = 0

  # Cached render state (copied from Terminal)
  @cached_fg : Termisu::Color?
  @cached_bg : Termisu::Color?
  @cached_attr : Termisu::Attribute = Termisu::Attribute::None
  @cached_cursor_visible : Bool?

  def initialize
    @cached_fg = nil
    @cached_bg = nil
    @cached_attr = Termisu::Attribute::None
    @cached_cursor_visible = nil
  end

  # Core write - captures all output
  def write(data : String)
    @writes << data
  end

  def flush
    @flush_count += 1
  end

  def size : {Int32, Int32}
    {80, 24}
  end

  def close; end

  def move_cursor(x : Int32, y : Int32)
    write("\e[#{y + 1};#{x + 1}H")
  end

  # Foreground with caching (same logic as Terminal)
  def foreground=(color : Termisu::Color)
    return if @cached_fg == color
    @cached_fg = color

    if color.default?
      write("\e[39m")
    else
      case color.mode
      when .ansi8?
        write("\e[3#{color.index}m")
      when .ansi256?
        write("\e[38;5;#{color.index}m")
      when .rgb?
        write("\e[38;2;#{color.r};#{color.g};#{color.b}m")
      end
    end
  end

  # Background with caching (same logic as Terminal)
  def background=(color : Termisu::Color)
    return if @cached_bg == color
    @cached_bg = color

    if color.default?
      write("\e[49m")
    else
      case color.mode
      when .ansi8?
        write("\e[4#{color.index}m")
      when .ansi256?
        write("\e[48;5;#{color.index}m")
      when .rgb?
        write("\e[48;2;#{color.r};#{color.g};#{color.b}m")
      end
    end
  end

  def write_show_cursor
    return if @cached_cursor_visible
    @cached_cursor_visible = true
    write("\e[?25h")
  end

  def write_hide_cursor
    cached = @cached_cursor_visible
    return if cached.is_a?(Bool) && !cached
    @cached_cursor_visible = false
    write("\e[?25l")
  end

  def reset_attributes
    write("\e[0m")
    @cached_fg = nil
    @cached_bg = nil
    @cached_attr = Termisu::Attribute::None
  end

  def enable_bold
    return if @cached_attr.bold?
    @cached_attr |= Termisu::Attribute::Bold
    write("\e[1m")
  end

  def enable_underline
    return if @cached_attr.underline?
    @cached_attr |= Termisu::Attribute::Underline
    write("\e[4m")
  end

  def enable_blink
    return if @cached_attr.blink?
    @cached_attr |= Termisu::Attribute::Blink
    write("\e[5m")
  end

  def enable_reverse
    return if @cached_attr.reverse?
    @cached_attr |= Termisu::Attribute::Reverse
    write("\e[7m")
  end

  def reset_render_state
    @cached_fg = nil
    @cached_bg = nil
    @cached_attr = Termisu::Attribute::None
    @cached_cursor_visible = nil
  end

  def clear_writes
    @writes.clear
  end

  def write_count : Int32
    @writes.size
  end
end

describe "Terminal State Caching" do
  describe "foreground color caching" do
    it "writes escape sequence on first call" do
      terminal = CaptureTerminal.new
      terminal.foreground = Termisu::Color.red
      terminal.writes.should contain("\e[31m")
    end

    it "skips redundant escape sequence for same color" do
      terminal = CaptureTerminal.new
      terminal.foreground = Termisu::Color.red
      initial_count = terminal.write_count

      terminal.foreground = Termisu::Color.red
      terminal.foreground = Termisu::Color.red

      terminal.write_count.should eq(initial_count)
    end

    it "writes escape sequence when color changes" do
      terminal = CaptureTerminal.new
      terminal.foreground = Termisu::Color.red
      terminal.clear_writes

      terminal.foreground = Termisu::Color.green

      terminal.writes.should contain("\e[32m")
    end

    it "handles ANSI-256 colors" do
      terminal = CaptureTerminal.new
      terminal.foreground = Termisu::Color.ansi256(208)
      terminal.writes.should contain("\e[38;5;208m")

      terminal.clear_writes
      terminal.foreground = Termisu::Color.ansi256(208)
      terminal.writes.should be_empty
    end

    it "handles RGB colors" do
      terminal = CaptureTerminal.new
      terminal.foreground = Termisu::Color.rgb(255, 128, 64)
      terminal.writes.should contain("\e[38;2;255;128;64m")

      terminal.clear_writes
      terminal.foreground = Termisu::Color.rgb(255, 128, 64)
      terminal.writes.should be_empty
    end

    it "handles default color" do
      terminal = CaptureTerminal.new
      terminal.foreground = Termisu::Color.default
      terminal.writes.should contain("\e[39m")

      terminal.clear_writes
      terminal.foreground = Termisu::Color.default
      terminal.writes.should be_empty
    end
  end

  describe "background color caching" do
    it "writes escape sequence on first call" do
      terminal = CaptureTerminal.new
      terminal.background = Termisu::Color.blue
      terminal.writes.should contain("\e[44m")
    end

    it "skips redundant escape sequence for same color" do
      terminal = CaptureTerminal.new
      terminal.background = Termisu::Color.blue
      initial_count = terminal.write_count

      terminal.background = Termisu::Color.blue
      terminal.background = Termisu::Color.blue

      terminal.write_count.should eq(initial_count)
    end

    it "writes escape sequence when color changes" do
      terminal = CaptureTerminal.new
      terminal.background = Termisu::Color.blue
      terminal.clear_writes

      terminal.background = Termisu::Color.yellow

      terminal.writes.should contain("\e[43m")
    end
  end

  describe "attribute caching" do
    it "writes bold on first enable" do
      terminal = CaptureTerminal.new
      terminal.enable_bold
      terminal.writes.should contain("\e[1m")
    end

    it "skips redundant bold enable" do
      terminal = CaptureTerminal.new
      terminal.enable_bold
      initial_count = terminal.write_count

      terminal.enable_bold
      terminal.enable_bold

      terminal.write_count.should eq(initial_count)
    end

    it "writes underline on first enable" do
      terminal = CaptureTerminal.new
      terminal.enable_underline
      terminal.writes.should contain("\e[4m")
    end

    it "skips redundant underline enable" do
      terminal = CaptureTerminal.new
      terminal.enable_underline
      initial_count = terminal.write_count

      terminal.enable_underline

      terminal.write_count.should eq(initial_count)
    end

    it "writes blink on first enable" do
      terminal = CaptureTerminal.new
      terminal.enable_blink
      terminal.writes.should contain("\e[5m")
    end

    it "writes reverse on first enable" do
      terminal = CaptureTerminal.new
      terminal.enable_reverse
      terminal.writes.should contain("\e[7m")
    end

    it "tracks multiple attributes independently" do
      terminal = CaptureTerminal.new
      terminal.enable_bold
      terminal.enable_underline
      terminal.writes.should contain("\e[1m")
      terminal.writes.should contain("\e[4m")

      # Both should be cached now
      terminal.clear_writes
      terminal.enable_bold
      terminal.enable_underline
      terminal.writes.should be_empty
    end
  end

  describe "cursor visibility caching" do
    it "writes show cursor on first call" do
      terminal = CaptureTerminal.new
      terminal.write_show_cursor
      terminal.writes.should contain("\e[?25h")
    end

    it "skips redundant show cursor" do
      terminal = CaptureTerminal.new
      terminal.write_show_cursor
      initial_count = terminal.write_count

      terminal.write_show_cursor
      terminal.write_show_cursor

      terminal.write_count.should eq(initial_count)
    end

    it "writes hide cursor on first call" do
      terminal = CaptureTerminal.new
      terminal.write_hide_cursor
      terminal.writes.should contain("\e[?25l")
    end

    it "skips redundant hide cursor" do
      terminal = CaptureTerminal.new
      terminal.write_hide_cursor
      initial_count = terminal.write_count

      terminal.write_hide_cursor
      terminal.write_hide_cursor

      terminal.write_count.should eq(initial_count)
    end

    it "writes when toggling visibility" do
      terminal = CaptureTerminal.new
      terminal.write_show_cursor
      terminal.clear_writes

      terminal.write_hide_cursor
      terminal.writes.should contain("\e[?25l")

      terminal.clear_writes
      terminal.write_show_cursor
      terminal.writes.should contain("\e[?25h")
    end
  end

  describe "#reset_render_state" do
    it "clears all cached state" do
      terminal = CaptureTerminal.new

      # Set up cached state
      terminal.foreground = Termisu::Color.red
      terminal.background = Termisu::Color.blue
      terminal.enable_bold
      terminal.write_show_cursor
      terminal.clear_writes

      # Verify caching works
      terminal.foreground = Termisu::Color.red
      terminal.background = Termisu::Color.blue
      terminal.enable_bold
      terminal.write_show_cursor
      terminal.writes.should be_empty

      # Reset and verify new calls emit sequences
      terminal.reset_render_state
      terminal.foreground = Termisu::Color.red
      terminal.background = Termisu::Color.blue
      terminal.enable_bold
      terminal.write_show_cursor

      terminal.writes.size.should be > 0
      terminal.writes.should contain("\e[31m")
      terminal.writes.should contain("\e[44m")
      terminal.writes.should contain("\e[1m")
      terminal.writes.should contain("\e[?25h")
    end
  end

  describe "#reset_attributes" do
    it "clears color and attribute cache" do
      terminal = CaptureTerminal.new

      # Set up cached state
      terminal.foreground = Termisu::Color.red
      terminal.background = Termisu::Color.blue
      terminal.enable_bold
      terminal.clear_writes

      # Reset attributes
      terminal.reset_attributes
      terminal.writes.should contain("\e[0m")

      terminal.clear_writes

      # Colors and attributes should emit again after reset
      terminal.foreground = Termisu::Color.red
      terminal.background = Termisu::Color.blue
      terminal.enable_bold

      terminal.writes.should contain("\e[31m")
      terminal.writes.should contain("\e[44m")
      terminal.writes.should contain("\e[1m")
    end
  end

  describe "performance optimization" do
    it "significantly reduces writes for repeated styling" do
      terminal = CaptureTerminal.new

      # Simulate rendering 100 cells with same style
      100.times do
        terminal.foreground = Termisu::Color.green
        terminal.background = Termisu::Color.black
        terminal.enable_bold
      end

      # Should only have 3 writes total (one for each: fg, bg, bold)
      terminal.write_count.should eq(3)
    end

    it "handles alternating styles efficiently" do
      terminal = CaptureTerminal.new

      # Simulate checkerboard pattern with 2 styles
      10.times do
        terminal.foreground = Termisu::Color.red
        terminal.foreground = Termisu::Color.blue
      end

      # Should have 20 writes (alternating pattern, no caching benefit)
      terminal.write_count.should eq(20)
    end

    it "demonstrates caching benefit with real-world scenario" do
      terminal = CaptureTerminal.new

      # Simulate rendering a status bar (same style across entire row)
      80.times do
        terminal.foreground = Termisu::Color.white
        terminal.background = Termisu::Color.blue
        terminal.enable_bold
        terminal.write("X") # Status bar character
      end

      # Should have: 3 style writes + 80 character writes = 83 total
      # Without caching, would be: 240 style writes + 80 character writes = 320
      terminal.write_count.should eq(83)
    end
  end

  describe "integration with Buffer rendering" do
    it "caching works through Renderer interface" do
      terminal = CaptureTerminal.new
      buffer = Termisu::Buffer.new(10, 5)

      # Set cells with same style
      buffer.set_cell(0, 0, 'A', fg: Termisu::Color.red)
      buffer.set_cell(1, 0, 'B', fg: Termisu::Color.red)
      buffer.set_cell(2, 0, 'C', fg: Termisu::Color.red)

      # Render using our capture terminal
      buffer.render_to(terminal)

      # The buffer's RenderState handles batching, so we should see "ABC" as single write
      # and only one foreground color set
      terminal.writes.count { |write| write.includes?("\e[31m") }.should eq(1)
    end
  end
end
