require "../../spec_helper"

# CaptureTerminal subclass that raises during rendering.
# Overrides size to ensure a non-zero buffer (unbuffer may report 0x0).
# move_cursor is called by Buffer#render_to during cell rendering,
# but NOT by end_sync_update (which only calls write + flush).
# This lets us test that the ensure block still emits ESU.
private class RaisingCaptureTerminal < CaptureTerminal
  property? fail_on_move_cursor : Bool = false

  def size : {Int32, Int32}
    {80, 24}
  end

  def move_cursor(x : Int32, y : Int32)
    raise "Simulated render failure" if @fail_on_move_cursor
    super
  end
end

describe "Synchronized Update Emission" do
  describe "#render" do
    it "emits BSU before content and ESU after when sync_updates enabled" do
      terminal = CaptureTerminal.new(sync_updates: true)

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
      terminal = CaptureTerminal.new(sync_updates: false)

      terminal.set_cell(0, 0, 'X')
      terminal.render

      output = terminal.output
      output.should_not contain(Termisu::Terminal::BSU)
      output.should_not contain(Termisu::Terminal::ESU)
    ensure
      terminal.try &.close
    end

    it "flushes exactly once when sync_updates enabled" do
      terminal = CaptureTerminal.new(sync_updates: true)

      terminal.set_cell(0, 0, 'X')
      terminal.render

      terminal.captured_flush_count.should eq(1)
    ensure
      terminal.try &.close
    end

    it "flushes exactly once when sync_updates disabled" do
      terminal = CaptureTerminal.new(sync_updates: false)

      terminal.set_cell(0, 0, 'X')
      terminal.render

      terminal.captured_flush_count.should eq(1)
    ensure
      terminal.try &.close
    end
  end

  describe "#sync" do
    it "emits BSU before content and ESU after when sync_updates enabled" do
      terminal = CaptureTerminal.new(sync_updates: true)

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
      terminal = CaptureTerminal.new(sync_updates: false)

      terminal.set_cell(0, 0, 'Y')
      terminal.sync

      output = terminal.output
      output.should_not contain(Termisu::Terminal::BSU)
      output.should_not contain(Termisu::Terminal::ESU)
    ensure
      terminal.try &.close
    end

    it "flushes exactly once when sync_updates enabled" do
      terminal = CaptureTerminal.new(sync_updates: true)

      terminal.set_cell(0, 0, 'Y')
      terminal.sync

      terminal.captured_flush_count.should eq(1)
    ensure
      terminal.try &.close
    end

    it "flushes exactly once when sync_updates disabled" do
      terminal = CaptureTerminal.new(sync_updates: false)

      terminal.set_cell(0, 0, 'Y')
      terminal.sync

      terminal.captured_flush_count.should eq(1)
    ensure
      terminal.try &.close
    end
  end

  describe "exception safety (BUG-001 regression)" do
    it "emits ESU even when render_to raises an exception" do
      terminal = RaisingCaptureTerminal.new(sync_updates: true)
      terminal.set_cell(0, 0, 'X')
      terminal.fail_on_move_cursor = true

      expect_raises(Exception, "Simulated render failure") do
        terminal.render
      end

      output = terminal.output
      output.should contain(Termisu::Terminal::BSU)
      output.should contain(Termisu::Terminal::ESU)

      # Verify BSU comes before ESU (proper pairing)
      bsu_pos = output.index(Termisu::Terminal::BSU).as(Int32)
      esu_pos = output.index(Termisu::Terminal::ESU).as(Int32)
      bsu_pos.should be < esu_pos
    ensure
      terminal.try &.close
    end

    it "emits ESU even when sync_to raises an exception" do
      terminal = RaisingCaptureTerminal.new(sync_updates: true)
      terminal.set_cell(0, 0, 'Y')
      terminal.fail_on_move_cursor = true

      expect_raises(Exception, "Simulated render failure") do
        terminal.sync
      end

      output = terminal.output
      output.should contain(Termisu::Terminal::BSU)
      output.should contain(Termisu::Terminal::ESU)

      bsu_pos = output.index(Termisu::Terminal::BSU).as(Int32)
      esu_pos = output.index(Termisu::Terminal::ESU).as(Int32)
      bsu_pos.should be < esu_pos
    ensure
      terminal.try &.close
    end

    it "flushes after ESU even when render_to raises" do
      terminal = RaisingCaptureTerminal.new(sync_updates: true)
      terminal.set_cell(0, 0, 'Z')
      terminal.fail_on_move_cursor = true

      expect_raises(Exception, "Simulated render failure") do
        terminal.render
      end

      # The ensure block should have flushed (ESU + flush)
      terminal.captured_flush_count.should eq(1)
    ensure
      terminal.try &.close
    end

    it "does not leave sync mode open on exception during render" do
      terminal = RaisingCaptureTerminal.new(sync_updates: true)
      terminal.set_cell(0, 0, 'A')
      terminal.fail_on_move_cursor = true

      expect_raises(Exception) do
        terminal.render
      end

      # Count BSU and ESU occurrences - should be equal (paired)
      output = terminal.output
      bsu_count = output.scan(Termisu::Terminal::BSU).size
      esu_count = output.scan(Termisu::Terminal::ESU).size
      bsu_count.should eq(esu_count)
    ensure
      terminal.try &.close
    end
  end

  describe "runtime toggle" do
    it "starts emitting BSU/ESU when enabled at runtime" do
      terminal = CaptureTerminal.new(sync_updates: false)

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
      terminal = CaptureTerminal.new(sync_updates: true)

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
