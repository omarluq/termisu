require "../spec_helper"

# Mock backend for testing RenderState
class MockRenderStateBackend < Termisu::Backend
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

  def show_cursor; end

  def hide_cursor; end

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
      backend = MockRenderStateBackend.new
      state = Termisu::RenderState.new

      changed = state.apply_style(backend, Termisu::Color.green, Termisu::Color.blue, Termisu::Attribute::None)

      changed.should be_true
      backend.fg_calls.should eq([Termisu::Color.green])
      backend.bg_calls.should eq([Termisu::Color.blue])
    end

    it "skips emission when style unchanged" do
      backend = MockRenderStateBackend.new
      state = Termisu::RenderState.new

      # First call - should emit
      state.apply_style(backend, Termisu::Color.green, Termisu::Color.blue, Termisu::Attribute::None)

      backend.fg_calls.clear
      backend.bg_calls.clear

      # Second call with same style - should not emit
      changed = state.apply_style(backend, Termisu::Color.green, Termisu::Color.blue, Termisu::Attribute::None)

      changed.should be_false
      backend.fg_calls.should be_empty
      backend.bg_calls.should be_empty
    end

    it "only emits foreground when only foreground changes" do
      backend = MockRenderStateBackend.new
      state = Termisu::RenderState.new

      state.apply_style(backend, Termisu::Color.green, Termisu::Color.blue, Termisu::Attribute::None)
      backend.fg_calls.clear
      backend.bg_calls.clear

      changed = state.apply_style(backend, Termisu::Color.red, Termisu::Color.blue, Termisu::Attribute::None)

      changed.should be_true
      backend.fg_calls.should eq([Termisu::Color.red])
      backend.bg_calls.should be_empty
    end

    it "only emits background when only background changes" do
      backend = MockRenderStateBackend.new
      state = Termisu::RenderState.new

      state.apply_style(backend, Termisu::Color.green, Termisu::Color.blue, Termisu::Attribute::None)
      backend.fg_calls.clear
      backend.bg_calls.clear

      changed = state.apply_style(backend, Termisu::Color.green, Termisu::Color.yellow, Termisu::Attribute::None)

      changed.should be_true
      backend.fg_calls.should be_empty
      backend.bg_calls.should eq([Termisu::Color.yellow])
    end

    it "enables bold attribute when added" do
      backend = MockRenderStateBackend.new
      state = Termisu::RenderState.new

      state.apply_style(backend, Termisu::Color.white, Termisu::Color.default, Termisu::Attribute::Bold)

      backend.bold_count.should eq(1)
    end

    it "enables underline attribute when added" do
      backend = MockRenderStateBackend.new
      state = Termisu::RenderState.new

      state.apply_style(backend, Termisu::Color.white, Termisu::Color.default, Termisu::Attribute::Underline)

      backend.underline_count.should eq(1)
    end

    it "enables multiple attributes at once" do
      backend = MockRenderStateBackend.new
      state = Termisu::RenderState.new

      state.apply_style(
        backend,
        Termisu::Color.white,
        Termisu::Color.default,
        Termisu::Attribute::Bold | Termisu::Attribute::Underline
      )

      backend.bold_count.should eq(1)
      backend.underline_count.should eq(1)
    end

    it "resets attributes when removing any" do
      backend = MockRenderStateBackend.new
      state = Termisu::RenderState.new

      # Set bold
      state.apply_style(backend, Termisu::Color.white, Termisu::Color.default, Termisu::Attribute::Bold)
      backend.reset_count.should eq(0)

      # Remove bold - should reset
      state.apply_style(backend, Termisu::Color.white, Termisu::Color.default, Termisu::Attribute::None)
      backend.reset_count.should eq(1)
    end

    it "resets then re-applies when changing attributes" do
      backend = MockRenderStateBackend.new
      state = Termisu::RenderState.new

      # Set bold
      state.apply_style(backend, Termisu::Color.white, Termisu::Color.default, Termisu::Attribute::Bold)

      # Change to underline only - should reset then apply underline
      state.apply_style(backend, Termisu::Color.white, Termisu::Color.default, Termisu::Attribute::Underline)

      backend.reset_count.should eq(1)
      backend.underline_count.should eq(1)
    end

    it "clears color state on reset" do
      backend = MockRenderStateBackend.new
      state = Termisu::RenderState.new

      # Set colors and bold
      state.apply_style(backend, Termisu::Color.green, Termisu::Color.blue, Termisu::Attribute::Bold)
      backend.fg_calls.clear
      backend.bg_calls.clear

      # Remove bold - resets, which clears color state
      state.apply_style(backend, Termisu::Color.green, Termisu::Color.blue, Termisu::Attribute::None)

      # Colors should be re-emitted because reset clears them
      backend.fg_calls.should eq([Termisu::Color.green])
      backend.bg_calls.should eq([Termisu::Color.blue])
    end
  end

  describe "#move_cursor" do
    it "emits move when cursor position is unknown" do
      backend = MockRenderStateBackend.new
      state = Termisu::RenderState.new

      moved = state.move_cursor(backend, 10, 5)

      moved.should be_true
      backend.move_calls.should eq([{10, 5}])
    end

    it "skips move when cursor already at position" do
      backend = MockRenderStateBackend.new
      state = Termisu::RenderState.new

      state.move_cursor(backend, 10, 5)
      backend.move_calls.clear

      moved = state.move_cursor(backend, 10, 5)

      moved.should be_false
      backend.move_calls.should be_empty
    end

    it "emits move when cursor moves to new position" do
      backend = MockRenderStateBackend.new
      state = Termisu::RenderState.new

      state.move_cursor(backend, 10, 5)
      backend.move_calls.clear

      moved = state.move_cursor(backend, 20, 10)

      moved.should be_true
      backend.move_calls.should eq([{20, 10}])
    end

    it "updates internal state" do
      backend = MockRenderStateBackend.new
      state = Termisu::RenderState.new

      state.move_cursor(backend, 10, 5)

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
