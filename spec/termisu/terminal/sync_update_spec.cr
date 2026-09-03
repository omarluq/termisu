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

private class OrderedFrameTerminfo < Termisu::Terminfo
  def cup_is_standard? : Bool
    true
  end

  def attrs_are_standard? : Bool
    true
  end

  def show_cursor_seq : String
    "\e[?12l\e[?25h"
  end

  def hide_cursor_seq : String
    "\e[?25l"
  end

  def reset_attrs_seq : String
    "\e[m\e(B"
  end
end

private class OrderedFrameTerminal < CaptureTerminal
  enum Failure
    Content
    Restoration
    Flush
  end

  CUP         = "\e[1;1H"
  HIDE_CURSOR = "\e[?25l"
  SHOW_CURSOR = "\e[?12l\e[?25h"
  property failure : Failure?
  getter events = [] of String

  @ordered_size : {Int32, Int32}
  @cup_writes : Int32 = 0

  def initialize(*, sync_updates : Bool, size : {Int32, Int32} = {3, 1})
    @ordered_size = size
    super(sync_updates: sync_updates, terminfo: OrderedFrameTerminfo.new)
  end

  def size : {Int32, Int32}
    @ordered_size
  end

  def write(data : String, columns_advanced = 0)
    capture_write(data)
    super(data)
  end

  def write(data : Bytes, columns_advanced = 0)
    text = String.new(data)
    capture_write(text)
    super(data, columns_advanced)
  end

  def flush
    @events << "<flush>"
    fail_once(Failure::Flush)
    super
  end

  def clear_events
    @events.clear
    @cup_writes = 0
    clear_captured
  end

  private def capture_write(data : String) : Nil
    @events << data
    if data == CUP
      @cup_writes += 1
      fail_once(Failure::Restoration) if @cup_writes == 2
    elsif data == "X"
      fail_once(Failure::Content)
    end
  end

  private def fail_once(phase : Failure) : Nil
    return unless @failure == phase

    @failure = nil
    raise "injected #{phase.to_s.downcase} failure"
  end
end

private class DirectFailureBackend < Termisu::Terminal::Backend
  enum Failure
    Write
    Flush
  end

  property failure : Failure?
  getter events = [] of String

  def size : {Int32, Int32}
    {3, 1}
  end

  def write(data : String)
    capture(data)
  end

  def write(data : Bytes)
    capture(String.new(data))
  end

  def flush
    @events << "<flush>"
    fail_once(Failure::Flush)
  end

  private def capture(data : String) : Nil
    @events << data
    fail_once(Failure::Write)
  end

  private def fail_once(phase : Failure) : Nil
    return unless @failure == phase

    @failure = nil
    raise "injected direct #{phase.to_s.downcase} failure"
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
  describe "clean frame fast path" do
    {false, true}.each do |sync_updates|
      suffix = sync_updates ? "with synchronized updates" : "without synchronized updates"
      frame_prefix = sync_updates ? [Termisu::Terminal::BSU] : [] of String
      frame_suffix = sync_updates ? [Termisu::Terminal::ESU, "<flush>"] : ["<flush>"]

      it "captures exact dirty frame ordering #{suffix}" do
        terminal = OrderedFrameTerminal.new(sync_updates: sync_updates)
        terminal.set_cell(0, 0, 'X')

        terminal.render

        terminal.events.should eq(
          frame_prefix + [OrderedFrameTerminal::CUP, OrderedFrameTerminal::HIDE_CURSOR, "\e[37;49m", "X",
                          OrderedFrameTerminal::CUP, OrderedFrameTerminal::HIDE_CURSOR] + frame_suffix
        )
        terminal.captured_flush_count.should eq(1)
      ensure
        terminal.try &.close
      end

      it "establishes the first clean frame and skips bytes on the second #{suffix}" do
        terminal = OrderedFrameTerminal.new(sync_updates: sync_updates)

        terminal.render
        terminal.events.should eq(
          frame_prefix + [OrderedFrameTerminal::CUP, OrderedFrameTerminal::HIDE_CURSOR,
                          OrderedFrameTerminal::CUP, OrderedFrameTerminal::HIDE_CURSOR] + frame_suffix
        )
        frame_bytes = terminal.events.reject { |event| event == "<flush>" }.sum(&.bytesize)
        frame_bytes.should eq(sync_updates ? 40 : 24)

        terminal.clear_events
        terminal.render
        terminal.events.should eq(["<flush>"])
        terminal.captured_flush_count.should eq(1)
      ensure
        terminal.try &.close
      end

      it "re-establishes a mutated cursor position #{suffix}" do
        terminal = OrderedFrameTerminal.new(sync_updates: sync_updates)
        terminal.render
        terminal.clear_events

        terminal.cursor.x = 1
        terminal.render

        terminal.events.should eq(
          frame_prefix + [OrderedFrameTerminal::CUP, OrderedFrameTerminal::HIDE_CURSOR,
                          "\e[1;2H", OrderedFrameTerminal::HIDE_CURSOR] + frame_suffix
        )

        terminal.clear_events
        terminal.render
        terminal.events.should eq(["<flush>"])
      ensure
        terminal.try &.close
      end

      it "re-establishes mutated cursor visibility #{suffix}" do
        terminal = OrderedFrameTerminal.new(sync_updates: sync_updates)
        terminal.render
        terminal.clear_events

        terminal.cursor.visible = true
        terminal.render

        terminal.events.should eq(
          frame_prefix + [OrderedFrameTerminal::CUP, OrderedFrameTerminal::HIDE_CURSOR,
                          OrderedFrameTerminal::CUP, OrderedFrameTerminal::SHOW_CURSOR, "\e[2 q"] + frame_suffix
        )

        terminal.clear_events
        terminal.render
        terminal.events.should eq(["<flush>"])
      ensure
        terminal.try &.close
      end

      it "restores a visible cursor before the final flush #{suffix}" do
        terminal = OrderedFrameTerminal.new(sync_updates: sync_updates)
        terminal.show_cursor
        terminal.clear_events

        terminal.render

        terminal.events.should eq(
          frame_prefix + [OrderedFrameTerminal::CUP, OrderedFrameTerminal::HIDE_CURSOR,
                          OrderedFrameTerminal::CUP, OrderedFrameTerminal::SHOW_CURSOR, "\e[2 q"] + frame_suffix
        )
        terminal.events[-2].should eq(sync_updates ? Termisu::Terminal::ESU : "\e[2 q")
        terminal.events.last.should eq("<flush>")

        terminal.clear_events
        terminal.render
        terminal.events.should eq(["<flush>"])
      ensure
        terminal.try &.close
      end

      it "flushes pending direct writes after re-establishing cursor state #{suffix}" do
        backend = DirectFailureBackend.new
        terminal = Termisu::Terminal.new(
          backend: backend,
          terminfo: OrderedFrameTerminfo.new,
          sync_updates: sync_updates
        )
        terminal.render
        backend.events.clear

        terminal.write("pending")
        terminal.render

        backend.events.should eq(
          ["pending"] + frame_prefix + [OrderedFrameTerminal::CUP, OrderedFrameTerminal::HIDE_CURSOR,
                                        OrderedFrameTerminal::CUP, OrderedFrameTerminal::HIDE_CURSOR] + frame_suffix
        )
      ensure
        terminal.try &.close
      end

      it "re-establishes a clean buffer after render state reset #{suffix}" do
        terminal = OrderedFrameTerminal.new(sync_updates: sync_updates)
        terminal.render
        terminal.clear_events
        terminal.reset_render_state

        terminal.render

        terminal.events.should eq(
          frame_prefix + [OrderedFrameTerminal::CUP, OrderedFrameTerminal::HIDE_CURSOR,
                          OrderedFrameTerminal::CUP, OrderedFrameTerminal::HIDE_CURSOR] + frame_suffix
        )
      ensure
        terminal.try &.close
      end

      it "preserves logical cursor state for a zero-size terminal #{suffix}" do
        terminal = OrderedFrameTerminal.new(sync_updates: sync_updates, size: {0, 0})
        terminal.move_cursor(7, 4)

        terminal.render

        terminal.events.should eq(
          frame_prefix + [OrderedFrameTerminal::HIDE_CURSOR,
                          OrderedFrameTerminal::HIDE_CURSOR] + frame_suffix
        )
        terminal.cursor.x.should eq(7)
        terminal.cursor.y.should eq(4)

        terminal.clear_events
        terminal.render
        terminal.events.should eq(["<flush>"])
      ensure
        terminal.try &.close
      end

      it "clears right-margin pending wrap before the final flush #{suffix}" do
        terminal = OrderedFrameTerminal.new(sync_updates: sync_updates)
        terminal.set_cell(0, 0, 'A')
        terminal.set_cell(1, 0, 'B')
        terminal.set_cell(2, 0, 'C')

        terminal.render

        terminal.events.should eq(
          frame_prefix + [OrderedFrameTerminal::CUP, OrderedFrameTerminal::HIDE_CURSOR, "\e[37;49m", "ABC",
                          OrderedFrameTerminal::CUP, OrderedFrameTerminal::HIDE_CURSOR] + frame_suffix
        )
      ensure
        terminal.try &.close
      end

      OrderedFrameTerminal::Failure.each do |failure|
        it "invalidates and retries after a #{failure.to_s.downcase} failure #{suffix}" do
          terminal = OrderedFrameTerminal.new(sync_updates: sync_updates)
          terminal.set_cell(0, 0, 'X')
          terminal.failure = failure

          expect_raises(Exception, "injected #{failure.to_s.downcase} failure") do
            terminal.render
          end

          terminal.clear_events
          terminal.render

          terminal.events.should contain("X  ")
          terminal.events.last.should eq("<flush>")
          terminal.events.count("<flush>").should eq(1)
          terminal.events.includes?(Termisu::Terminal::BSU).should eq(sync_updates)
          terminal.events.includes?(Termisu::Terminal::ESU).should eq(sync_updates)
        ensure
          terminal.try &.close
        end
      end

      it "invalidates an established clean frame when its flush fails #{suffix}" do
        terminal = OrderedFrameTerminal.new(sync_updates: sync_updates)
        terminal.set_cell(0, 0, 'X')
        terminal.render
        terminal.clear_events
        terminal.failure = OrderedFrameTerminal::Failure::Flush

        expect_raises(Exception, "injected flush failure") { terminal.render }

        terminal.clear_events
        terminal.render
        terminal.events.should contain("X  ")
        terminal.events.last.should eq("<flush>")
      ensure
        terminal.try &.close
      end

      it "never shortcuts an explicit sync #{suffix}" do
        terminal = OrderedFrameTerminal.new(sync_updates: sync_updates)
        terminal.render
        terminal.clear_events

        terminal.sync

        terminal.events.should contain("   ")
        terminal.events.last.should eq("<flush>")
        terminal.events.includes?(Termisu::Terminal::BSU).should eq(sync_updates)
        terminal.events.includes?(Termisu::Terminal::ESU).should eq(sync_updates)
      ensure
        terminal.try &.close
      end

      {"write", "move", "visibility", "flush"}.each do |operation|
        it "re-establishes after a direct #{operation} failure #{suffix}" do
          backend = DirectFailureBackend.new
          terminal = Termisu::Terminal.new(
            backend: backend,
            terminfo: OrderedFrameTerminfo.new,
            sync_updates: sync_updates
          )
          terminal.render
          backend.events.clear

          if operation == "flush"
            backend.failure = DirectFailureBackend::Failure::Flush
            expect_raises(Exception, "injected direct flush failure") { terminal.flush }
          else
            backend.failure = DirectFailureBackend::Failure::Write
            expect_raises(Exception, "injected direct write failure") do
              case operation
              when "write"      then terminal.write("pending")
              when "move"       then terminal.move_cursor(1, 0)
              when "visibility" then terminal.show_cursor
              end
            end
          end

          backend.events.clear
          terminal.render

          backend.events.should contain("   ")
          backend.events.should contain(OrderedFrameTerminal::CUP)
          backend.events.should contain(OrderedFrameTerminal::HIDE_CURSOR)
          backend.events.last.should eq("<flush>")
          backend.events.count("<flush>").should eq(1)
          backend.events.includes?(Termisu::Terminal::BSU).should eq(sync_updates)
          backend.events.includes?(Termisu::Terminal::ESU).should eq(sync_updates)
        ensure
          terminal.try &.close
        end
      end
    end
  end

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
