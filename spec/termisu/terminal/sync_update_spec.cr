require "../../spec_helper"

describe "Synchronized Update Emission" do
  describe "#render" do
    it "emits BSU before content and ESU after when sync_updates enabled" do
      terminal = TestTerminal.new(sync_updates: true)

      # Write a cell to ensure there's content to render
      terminal.set_cell(0, 0, 'X')
      terminal.render

      output = terminal.output
      output.should contain(Termisu::Terminal::BSU)
      output.should contain(Termisu::Terminal::ESU)

      # Verify BSU comes before ESU
      bsu_pos = output.index(Termisu::Terminal::BSU).as(Int32)
      esu_pos = output.index(Termisu::Terminal::ESU).as(Int32)
      bsu_pos.should be < esu_pos
    ensure
      terminal.try &.close
    end

    it "does not emit BSU/ESU when sync_updates disabled" do
      terminal = TestTerminal.new(sync_updates: false)

      terminal.set_cell(0, 0, 'X')
      terminal.render

      output = terminal.output
      output.should_not contain(Termisu::Terminal::BSU)
      output.should_not contain(Termisu::Terminal::ESU)
    ensure
      terminal.try &.close
    end

    it "flushes exactly once when sync_updates enabled" do
      terminal = TestTerminal.new(sync_updates: true)

      terminal.set_cell(0, 0, 'X')
      terminal.render

      terminal.captured_flush_count.should eq(1)
    ensure
      terminal.try &.close
    end

    it "flushes exactly once when sync_updates disabled" do
      terminal = TestTerminal.new(sync_updates: false)

      terminal.set_cell(0, 0, 'X')
      terminal.render

      terminal.captured_flush_count.should eq(1)
    ensure
      terminal.try &.close
    end
  end

  describe "#sync" do
    it "emits BSU before content and ESU after when sync_updates enabled" do
      terminal = TestTerminal.new(sync_updates: true)

      terminal.set_cell(0, 0, 'Y')
      terminal.sync

      output = terminal.output
      output.should contain(Termisu::Terminal::BSU)
      output.should contain(Termisu::Terminal::ESU)

      # Verify BSU comes before ESU
      bsu_pos = output.index(Termisu::Terminal::BSU).as(Int32)
      esu_pos = output.index(Termisu::Terminal::ESU).as(Int32)
      bsu_pos.should be < esu_pos
    ensure
      terminal.try &.close
    end

    it "does not emit BSU/ESU when sync_updates disabled" do
      terminal = TestTerminal.new(sync_updates: false)

      terminal.set_cell(0, 0, 'Y')
      terminal.sync

      output = terminal.output
      output.should_not contain(Termisu::Terminal::BSU)
      output.should_not contain(Termisu::Terminal::ESU)
    ensure
      terminal.try &.close
    end

    it "flushes exactly once when sync_updates enabled" do
      terminal = TestTerminal.new(sync_updates: true)

      terminal.set_cell(0, 0, 'Y')
      terminal.sync

      terminal.captured_flush_count.should eq(1)
    ensure
      terminal.try &.close
    end

    it "flushes exactly once when sync_updates disabled" do
      terminal = TestTerminal.new(sync_updates: false)

      terminal.set_cell(0, 0, 'Y')
      terminal.sync

      terminal.captured_flush_count.should eq(1)
    ensure
      terminal.try &.close
    end
  end

  describe "runtime toggle" do
    it "starts emitting BSU/ESU when enabled at runtime" do
      terminal = TestTerminal.new(sync_updates: false)

      terminal.set_cell(0, 0, 'A')
      terminal.render
      terminal.output.should_not contain(Termisu::Terminal::BSU)

      terminal.clear_captured
      terminal.sync_updates = true

      terminal.set_cell(1, 0, 'B')
      terminal.render
      terminal.output.should contain(Termisu::Terminal::BSU)
      terminal.output.should contain(Termisu::Terminal::ESU)
    ensure
      terminal.try &.close
    end

    it "stops emitting BSU/ESU when disabled at runtime" do
      terminal = TestTerminal.new(sync_updates: true)

      terminal.set_cell(0, 0, 'A')
      terminal.render
      terminal.output.should contain(Termisu::Terminal::BSU)

      terminal.clear_captured
      terminal.sync_updates = false

      terminal.set_cell(1, 0, 'B')
      terminal.render
      terminal.output.should_not contain(Termisu::Terminal::BSU)
      terminal.output.should_not contain(Termisu::Terminal::ESU)
    ensure
      terminal.try &.close
    end
  end
end
