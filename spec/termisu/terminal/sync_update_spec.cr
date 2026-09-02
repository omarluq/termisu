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

private class PrimaryAndCleanupFaultTerminal < CaptureTerminal
  enum CleanupPhase
    EsuWrite
    Flush
  end

  property cleanup_phase : CleanupPhase?
  getter? cleanup_failed : Bool = false

  def size : {Int32, Int32}
    {3, 1}
  end

  def move_cursor(x : Int32, y : Int32)
    raise "primary render failure"
  end

  def write(data : String, columns_advanced = 0)
    if data == Termisu::Terminal::ESU && @cleanup_phase == CleanupPhase::EsuWrite
      @cleanup_failed = true
      raise "cleanup ESU failure"
    end
    @writes << data
  end

  def flush
    if @cleanup_phase == CleanupPhase::Flush
      @cleanup_failed = true
      raise "cleanup flush failure"
    end
    super
  end
end

private class SyncFaultTerminal < CaptureTerminal
  enum Phase
    Begin
    Move
    Sgr
    Write
    End
    Flush
  end

  property fail_phase : Phase?
  getter? failed : Bool = false

  def size : {Int32, Int32}
    {3, 1}
  end

  def move_cursor(x : Int32, y : Int32)
    fail_once(Phase::Move)
    super
  end

  def write(data : String, columns_advanced = 0)
    if data == Termisu::Terminal::BSU
      fail_once(Phase::Begin)
    elsif data == Termisu::Terminal::ESU
      fail_once(Phase::End)
    end
    @writes << data
  end

  def write(data : Bytes, columns_advanced = 0)
    text = String.new(data)
    if text.starts_with?('\e') && text.ends_with?('m')
      fail_once(Phase::Sgr)
    else
      fail_once(Phase::Write)
    end
    @writes << text
  end

  def flush
    fail_once(Phase::Flush)
    super
  end

  private def fail_once(phase : Phase) : Nil
    return if @fail_phase != phase || @failed

    @failed = true
    raise "injected #{phase} failure"
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

  describe "transaction retries" do
    SyncFaultTerminal::Phase.each do |phase|
      it "fully retries an unstyled frame after a synchronized-update #{phase.to_s.downcase} failure" do
        terminal = SyncFaultTerminal.new(sync_updates: true)
        terminal.set_cell(0, 0, 'X', attr: Termisu::Attribute::Bold)
        terminal.render

        terminal.clear_captured
        terminal.set_cell(0, 0, 'Y', attr: Termisu::Attribute::None)
        terminal.fail_phase = phase
        expect_raises(Exception, "injected #{phase} failure") do
          terminal.render
        end

        terminal.failed?.should be_true
        terminal.clear_captured
        terminal.render

        content_writes = terminal.writes.reject(&.starts_with?('\e'))
        content_writes.join.should eq("Y  ")
        terminal.output.should contain(Termisu::Terminal::BSU)
        terminal.output.should contain(Termisu::Terminal::ESU)
        terminal.output.should contain("\e[m")
        terminal.captured_flush_count.should eq(1)
      ensure
        terminal.try &.close
      end
    end
  end

  describe "compound transaction failures" do
    PrimaryAndCleanupFaultTerminal::CleanupPhase.each do |cleanup_phase|
      it "preserves the rendering error when #{cleanup_phase.to_s.underscore} cleanup also fails" do
        terminal = PrimaryAndCleanupFaultTerminal.new(sync_updates: true)
        terminal.set_cell(0, 0, 'X')
        terminal.cleanup_phase = cleanup_phase

        expect_raises(Exception, "primary render failure") do
          terminal.render
        end
        terminal.cleanup_failed?.should be_true
      ensure
        terminal.try &.close
      end
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

      # Count BSU and ESU occurrences - should be exactly 1 each (paired)
      output = terminal.output
      bsu_count = output.scan(Termisu::Terminal::BSU).size
      esu_count = output.scan(Termisu::Terminal::ESU).size
      bsu_count.should eq(1)
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
