require "../spec_helper"

# Mock renderer for testing RenderState
class MockRenderStateRenderer < Termisu::Renderer
  property fg_calls : Array(Termisu::Color) = [] of Termisu::Color
  property bg_calls : Array(Termisu::Color) = [] of Termisu::Color
  property move_calls : Array({Int32, Int32}) = [] of {Int32, Int32}
  property reset_count : Int32 = 0
  property bold_count : Int32 = 0
  property underline_count : Int32 = 0
  property reverse_count : Int32 = 0
  property blink_count : Int32 = 0

  def write(data : String); end

  def move_cursor(x : Int32, y : Int32)
    @move_calls << {x, y}
  end

  def foreground=(color : Termisu::Color)
    @fg_calls << color
  end

  def background=(color : Termisu::Color)
    @bg_calls << color
  end

  def flush; end

  def reset_attributes
    @reset_count += 1
  end

  def enable_bold
    @bold_count += 1
  end

  def enable_underline
    @underline_count += 1
  end

  def enable_blink
    @blink_count += 1
  end

  def enable_reverse
    @reverse_count += 1
  end

  def write_show_cursor; end

  def write_hide_cursor; end

  def size : {Int32, Int32}
    {80, 24}
  end

  def close; end
end

describe Termisu::RenderState do
  describe ".new" do
    it "initializes with nil/unknown state" do
      state = Termisu::RenderState.new
      state.fg.should be_nil
      state.bg.should be_nil
      state.attr.should eq(Termisu::Attribute::None)
      state.cursor_x.should be_nil
      state.cursor_y.should be_nil
    end
  end

  describe "#reset" do
    it "resets all state to unknown" do
      state = Termisu::RenderState.new
      state.fg = Termisu::Color.red
      state.bg = Termisu::Color.blue
      state.attr = Termisu::Attribute::Bold
      state.cursor_x = 10
      state.cursor_y = 5

      state.reset

      state.fg.should be_nil
      state.bg.should be_nil
      state.attr.should eq(Termisu::Attribute::None)
      state.cursor_x.should be_nil
      state.cursor_y.should be_nil
    end
  end

  describe "#apply_style" do
    it "emits all sequences when state is unknown" do
      renderer = MockRenderStateRenderer.new
      state = Termisu::RenderState.new

      changed = state.apply_style(renderer, Termisu::Color.green, Termisu::Color.blue, Termisu::Attribute::None)

      changed.should be_true
      renderer.fg_calls.should eq([Termisu::Color.green])
      renderer.bg_calls.should eq([Termisu::Color.blue])
    end

    it "skips emission when style unchanged" do
      renderer = MockRenderStateRenderer.new
      state = Termisu::RenderState.new

      # First call - should emit
      state.apply_style(renderer, Termisu::Color.green, Termisu::Color.blue, Termisu::Attribute::None)

      renderer.fg_calls.clear
      renderer.bg_calls.clear

      # Second call with same style - should not emit
      changed = state.apply_style(renderer, Termisu::Color.green, Termisu::Color.blue, Termisu::Attribute::None)

      changed.should be_false
      renderer.fg_calls.should be_empty
      renderer.bg_calls.should be_empty
    end

    it "only emits foreground when only foreground changes" do
      renderer = MockRenderStateRenderer.new
      state = Termisu::RenderState.new

      state.apply_style(renderer, Termisu::Color.green, Termisu::Color.blue, Termisu::Attribute::None)
      renderer.fg_calls.clear
      renderer.bg_calls.clear

      changed = state.apply_style(renderer, Termisu::Color.red, Termisu::Color.blue, Termisu::Attribute::None)

      changed.should be_true
      renderer.fg_calls.should eq([Termisu::Color.red])
      renderer.bg_calls.should be_empty
    end

    it "only emits background when only background changes" do
      renderer = MockRenderStateRenderer.new
      state = Termisu::RenderState.new

      state.apply_style(renderer, Termisu::Color.green, Termisu::Color.blue, Termisu::Attribute::None)
      renderer.fg_calls.clear
      renderer.bg_calls.clear

      changed = state.apply_style(renderer, Termisu::Color.green, Termisu::Color.yellow, Termisu::Attribute::None)

      changed.should be_true
      renderer.fg_calls.should be_empty
      renderer.bg_calls.should eq([Termisu::Color.yellow])
    end

    it "enables bold attribute when added" do
      renderer = MockRenderStateRenderer.new
      state = Termisu::RenderState.new

      state.apply_style(renderer, Termisu::Color.white, Termisu::Color.default, Termisu::Attribute::Bold)

      renderer.bold_count.should eq(1)
    end

    it "enables underline attribute when added" do
      renderer = MockRenderStateRenderer.new
      state = Termisu::RenderState.new

      state.apply_style(renderer, Termisu::Color.white, Termisu::Color.default, Termisu::Attribute::Underline)

      renderer.underline_count.should eq(1)
    end

    it "enables multiple attributes at once" do
      renderer = MockRenderStateRenderer.new
      state = Termisu::RenderState.new

      state.apply_style(
        renderer,
        Termisu::Color.white,
        Termisu::Color.default,
        Termisu::Attribute::Bold | Termisu::Attribute::Underline
      )

      renderer.bold_count.should eq(1)
      renderer.underline_count.should eq(1)
    end

    it "resets attributes when removing any" do
      renderer = MockRenderStateRenderer.new
      state = Termisu::RenderState.new

      # Set bold
      state.apply_style(renderer, Termisu::Color.white, Termisu::Color.default, Termisu::Attribute::Bold)
      renderer.reset_count.should eq(0)

      # Remove bold - should reset
      state.apply_style(renderer, Termisu::Color.white, Termisu::Color.default, Termisu::Attribute::None)
      renderer.reset_count.should eq(1)
    end

    it "resets then re-applies when changing attributes" do
      renderer = MockRenderStateRenderer.new
      state = Termisu::RenderState.new

      # Set bold
      state.apply_style(renderer, Termisu::Color.white, Termisu::Color.default, Termisu::Attribute::Bold)

      # Change to underline only - should reset then apply underline
      state.apply_style(renderer, Termisu::Color.white, Termisu::Color.default, Termisu::Attribute::Underline)

      renderer.reset_count.should eq(1)
      renderer.underline_count.should eq(1)
    end

    it "clears color state on reset" do
      renderer = MockRenderStateRenderer.new
      state = Termisu::RenderState.new

      # Set colors and bold
      state.apply_style(renderer, Termisu::Color.green, Termisu::Color.blue, Termisu::Attribute::Bold)
      renderer.fg_calls.clear
      renderer.bg_calls.clear

      # Remove bold - resets, which clears color state
      state.apply_style(renderer, Termisu::Color.green, Termisu::Color.blue, Termisu::Attribute::None)

      # Colors should be re-emitted because reset clears them
      renderer.fg_calls.should eq([Termisu::Color.green])
      renderer.bg_calls.should eq([Termisu::Color.blue])
    end
  end

  describe "#move_cursor" do
    it "emits move when cursor position is unknown" do
      renderer = MockRenderStateRenderer.new
      state = Termisu::RenderState.new

      moved = state.move_cursor(renderer, 10, 5)

      moved.should be_true
      renderer.move_calls.should eq([{10, 5}])
    end

    it "skips move when cursor already at position" do
      renderer = MockRenderStateRenderer.new
      state = Termisu::RenderState.new

      state.move_cursor(renderer, 10, 5)
      renderer.move_calls.clear

      moved = state.move_cursor(renderer, 10, 5)

      moved.should be_false
      renderer.move_calls.should be_empty
    end

    it "emits move when cursor moves to new position" do
      renderer = MockRenderStateRenderer.new
      state = Termisu::RenderState.new

      state.move_cursor(renderer, 10, 5)
      renderer.move_calls.clear

      moved = state.move_cursor(renderer, 20, 10)

      moved.should be_true
      renderer.move_calls.should eq([{20, 10}])
    end

    it "updates internal state" do
      renderer = MockRenderStateRenderer.new
      state = Termisu::RenderState.new

      state.move_cursor(renderer, 10, 5)

      state.cursor_x.should eq(10)
      state.cursor_y.should eq(5)
    end
  end

  describe "#advance_cursor" do
    it "increments cursor x position" do
      state = Termisu::RenderState.new
      state.cursor_x = 10
      state.cursor_y = 5

      state.advance_cursor

      state.cursor_x.should eq(11)
      state.cursor_y.should eq(5)
    end

    it "does nothing when cursor position unknown" do
      state = Termisu::RenderState.new

      state.advance_cursor

      state.cursor_x.should be_nil
    end
  end

  describe "#cursor_at?" do
    it "returns true when cursor at position" do
      state = Termisu::RenderState.new
      state.cursor_x = 10
      state.cursor_y = 5

      state.cursor_at?(10, 5).should be_true
    end

    it "returns false when cursor at different position" do
      state = Termisu::RenderState.new
      state.cursor_x = 10
      state.cursor_y = 5

      state.cursor_at?(20, 10).should be_false
    end

    it "returns false when cursor position unknown" do
      state = Termisu::RenderState.new

      state.cursor_at?(10, 5).should be_false
    end
  end
end
