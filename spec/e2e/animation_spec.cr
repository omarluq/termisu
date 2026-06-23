require "./e2e_helper"

# Port of e2e/tests/animation.test.ts — drives bin/animation. No snapshot:
# the frame/spinner change every tick (intentionally, like the TS suite).
private def with_animation(&)
  requires_binary "bin/animation"
  Termisu::Testing.terminal("bin/animation", cols: 100, rows: 50) do |term|
    term.get_by_text(/Target: \d+fps/).should be_true
    yield term
  end
end

describe "Animation example (e2e)" do
  describe "initial rendering" do
    it "shows the timer type, FPS stats and ball" do
      with_animation do |term|
        term.get_by_text(/Timer \(sleep-based\)/).should be_true
        term.get_by_text(/Target: \d+fps/).should be_true
        term.get_by_text(/Actual: \d+\.?\d*fps/).should be_true
        term.get_by_text("●").should be_true
      end
    end

    it "shows the controls bar" do
      with_animation do |term|
        term.get_by_text(/Q=quit/).should be_true
        term.get_by_text(/T=timer/).should be_true
        term.get_by_text(/SPACE=pause/).should be_true
        term.get_by_text(/R=record/).should be_true
      end
    end
  end

  describe "stats display" do
    it "shows target/actual with interval and pipe separators" do
      with_animation do |term|
        term.get_by_text(/Target: \d+fps \(\d+\.?\d*ms\)/).should be_true
        term.get_by_text(/Actual: \d+\.?\d*fps \(\d+\.?\d*ms\)/).should be_true
        term.get_by_text(/Target:.*\|.*Actual:/).should be_true
      end
    end
  end

  describe "animation progression" do
    it "moves the ball over time" do
      with_animation do |term|
        start = term.locate("●")
        start.should_not be_nil

        moved = false
        deadline = monotonic_now + 3.seconds
        while monotonic_now < deadline
          sleep 50.milliseconds
          if term.find("●") != start
            moved = true
            break
          end
        end
        moved.should be_true
      end
    end
  end

  describe "layout snapshot" do
    it "matches the chrome snapshot (moving ball + live FPS masked)" do
      with_animation do |term|
        assert_snapshot(term, "animation", mask: [
          /●/,                              # moving ball
          /Actual: [\d.]+fps \([\d.]+ms\)/, # live FPS readout
          / SLOW/,                          # perf warning (fires on loaded CI runners)
          / MISSED:\d+/,                    # dropped-frame counter
          / PAUSED/,                        # pause indicator
        ])
      end
    end
  end

  describe "exit handling" do
    it "exits on 'q'" do
      with_animation(&.write("q"))
    end

    it "exits on ESC" do
      with_animation(&.key(:esc))
    end

    it "keeps running on an unrelated key" do
      with_animation do |term|
        term.write("x")
        term.get_by_text(/Q=quit/).should be_true
      end
    end
  end
end
