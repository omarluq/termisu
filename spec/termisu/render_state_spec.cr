require "../spec_helper"

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
      renderer = MockRenderer.new
      state = Termisu::RenderState.new

      changed = state.apply_style(renderer, Termisu::Color.green, Termisu::Color.blue, Termisu::Attribute::None)

      changed.should be_true
      renderer.fg_calls.should eq([Termisu::Color.green])
      renderer.bg_calls.should eq([Termisu::Color.blue])
    end

    it "skips emission when style unchanged" do
      renderer = MockRenderer.new
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
      renderer = MockRenderer.new
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
      renderer = MockRenderer.new
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
      renderer = MockRenderer.new
      state = Termisu::RenderState.new

      state.apply_style(renderer, Termisu::Color.white, Termisu::Color.default, Termisu::Attribute::Bold)

      renderer.bold_count.should eq(1)
    end

    it "enables underline attribute when added" do
      renderer = MockRenderer.new
      state = Termisu::RenderState.new

      state.apply_style(renderer, Termisu::Color.white, Termisu::Color.default, Termisu::Attribute::Underline)

      renderer.underline_count.should eq(1)
    end

    it "enables multiple attributes at once" do
      renderer = MockRenderer.new
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
      renderer = MockRenderer.new
      state = Termisu::RenderState.new

      # Set bold
      state.apply_style(renderer, Termisu::Color.white, Termisu::Color.default, Termisu::Attribute::Bold)
      renderer.reset_count.should eq(0)

      # Remove bold - should reset
      state.apply_style(renderer, Termisu::Color.white, Termisu::Color.default, Termisu::Attribute::None)
      renderer.reset_count.should eq(1)
    end

    it "resets then re-applies when changing attributes" do
      renderer = MockRenderer.new
      state = Termisu::RenderState.new

      # Set bold
      state.apply_style(renderer, Termisu::Color.white, Termisu::Color.default, Termisu::Attribute::Bold)

      # Change to underline only - should reset then apply underline
      state.apply_style(renderer, Termisu::Color.white, Termisu::Color.default, Termisu::Attribute::Underline)

      renderer.reset_count.should eq(1)
      renderer.underline_count.should eq(1)
    end

    it "clears color state on reset" do
      renderer = MockRenderer.new
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
      renderer = MockRenderer.new
      state = Termisu::RenderState.new

      moved = state.move_cursor(renderer, 10, 5)

      moved.should be_true
      renderer.move_calls.should eq([{10, 5}])
    end

    it "skips move when cursor already at position" do
      renderer = MockRenderer.new
      state = Termisu::RenderState.new

      state.move_cursor(renderer, 10, 5)
      renderer.move_calls.clear

      moved = state.move_cursor(renderer, 10, 5)

      moved.should be_false
      renderer.move_calls.should be_empty
    end

    it "emits move when cursor moves to new position" do
      renderer = MockRenderer.new
      state = Termisu::RenderState.new

      state.move_cursor(renderer, 10, 5)
      renderer.move_calls.clear

      moved = state.move_cursor(renderer, 20, 10)

      moved.should be_true
      renderer.move_calls.should eq([{20, 10}])
    end

    it "updates internal state" do
      renderer = MockRenderer.new
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

  describe "extended attribute handling" do
    it "enables dim attribute when added" do
      renderer = MockRenderer.new
      state = Termisu::RenderState.new

      state.apply_style(renderer, Termisu::Color.white, Termisu::Color.default, Termisu::Attribute::Dim)

      renderer.dim_count.should eq(1)
    end

    it "enables cursive attribute when added" do
      renderer = MockRenderer.new
      state = Termisu::RenderState.new

      state.apply_style(renderer, Termisu::Color.white, Termisu::Color.default, Termisu::Attribute::Cursive)

      renderer.cursive_count.should eq(1)
    end

    it "enables hidden attribute when added" do
      renderer = MockRenderer.new
      state = Termisu::RenderState.new

      state.apply_style(renderer, Termisu::Color.white, Termisu::Color.default, Termisu::Attribute::Hidden)

      renderer.hidden_count.should eq(1)
    end

    it "enables multiple extended attributes at once" do
      renderer = MockRenderer.new
      state = Termisu::RenderState.new

      state.apply_style(
        renderer,
        Termisu::Color.white,
        Termisu::Color.default,
        Termisu::Attribute::Dim | Termisu::Attribute::Cursive | Termisu::Attribute::Hidden
      )

      renderer.dim_count.should eq(1)
      renderer.cursive_count.should eq(1)
      renderer.hidden_count.should eq(1)
    end

    it "combines basic and extended attributes" do
      renderer = MockRenderer.new
      state = Termisu::RenderState.new

      state.apply_style(
        renderer,
        Termisu::Color.white,
        Termisu::Color.default,
        Termisu::Attribute::Bold | Termisu::Attribute::Dim | Termisu::Attribute::Cursive
      )

      renderer.bold_count.should eq(1)
      renderer.dim_count.should eq(1)
      renderer.cursive_count.should eq(1)
    end

    it "does not re-enable already set extended attributes" do
      renderer = MockRenderer.new
      state = Termisu::RenderState.new

      state.apply_style(renderer, Termisu::Color.white, Termisu::Color.default, Termisu::Attribute::Dim)
      initial_dim_count = renderer.dim_count

      # Apply same attribute again
      state.apply_style(renderer, Termisu::Color.white, Termisu::Color.default, Termisu::Attribute::Dim)

      renderer.dim_count.should eq(initial_dim_count)
    end

    it "resets when removing extended attributes" do
      renderer = MockRenderer.new
      state = Termisu::RenderState.new

      # Set dim
      state.apply_style(renderer, Termisu::Color.white, Termisu::Color.default, Termisu::Attribute::Dim)
      renderer.reset_count.should eq(0)

      # Remove dim - should reset
      state.apply_style(renderer, Termisu::Color.white, Termisu::Color.default, Termisu::Attribute::None)
      renderer.reset_count.should eq(1)
    end
  end
end
