require "./e2e_helper"

# Port of e2e/tests/simple.test.ts to the Crystal-native harness.
describe "Simple example (e2e)" do
  it "displays the greeting and strikethrough text" do
    requires_binary "bin/simple"
    Termisu::Testing.terminal("bin/simple", cols: 100, rows: 50) do |term|
      term.get_by_text("Hi").should be_true
      term.get_by_text("Strikethrough").should be_true
    end
  end

  it "positions the cursor after the strikethrough text" do
    requires_binary "bin/simple"
    Termisu::Testing.terminal("bin/simple", cols: 100, rows: 50) do |term|
      term.get_by_text("Strikethrough").should be_true
      # set_cursor(14, 1) in the example
      term.cursor.should eq({14, 1})
    end
  end

  it "responds to a key press" do
    requires_binary "bin/simple"
    Termisu::Testing.terminal("bin/simple", cols: 100, rows: 50) do |term|
      term.get_by_text("Hi").should be_true
      term.write("a")
      term.get_by_text(/You pressed:.*'a'/).should be_true
    end
  end

  it "matches the initial-render snapshot" do
    requires_binary "bin/simple"
    Termisu::Testing.terminal("bin/simple", cols: 100, rows: 50) do |term|
      term.get_by_text("Strikethrough").should be_true
      assert_snapshot(term, "simple")
    end
  end
end
