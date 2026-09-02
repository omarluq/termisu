require "../spec_helper"

private def termisu_error_message : String
  len = termisu_last_error_length
  return "" if len == 0_u64

  bytes = Bytes.new(len.to_i + 1, 0_u8)
  copied = termisu_last_error_copy(bytes.to_unsafe, bytes.size.to_u64)
  copied.should be <= len
  String.new(bytes.to_unsafe)
end

private def default_ffi_style : Termisu::FFI::ABI::CellStyle
  style = uninitialized Termisu::FFI::ABI::CellStyle
  style.fg.mode = Termisu::FFI::ColorMode::Default.value
  style.fg.index = -1
  style.fg.r = 0_u8
  style.fg.g = 0_u8
  style.fg.b = 0_u8
  style.bg = style.fg
  style.attr = 0_u16
  style
end

private def ffi_cell_op(x : Int32, y : Int32, codepoint : Int32) : Termisu::FFI::ABI::CellOp
  op = uninitialized Termisu::FFI::ABI::CellOp
  op.x = x
  op.y = y
  op.codepoint = codepoint
  op.style = default_ffi_style
  op
end

private def assert_ffi_blocking_poll_cancelled(*, destroy : Bool) : Nil
  handle = termisu_create(0_u8)
  handle.should_not eq(0_u64)
  context = Termisu::FFI::Registry.fetch(handle) || fail("created FFI context was not registered")
  poll_status = Atomic(Int32).new(Int32::MIN)

  poll_thread = Thread.new do
    event = uninitialized Termisu::FFI::ABI::Event
    poll_status.set(termisu_poll_event(handle, -1, pointerof(event)))
  end

  deadline = monotonic_now + 5.seconds
  until context.operations_in_flight?
    raise "exported blocking poll did not start" if monotonic_now >= deadline
    sleep 1.millisecond
  end

  # Invoke the exported shutdown concurrently with the poll. A regression here
  # blocks this call indefinitely instead of reaching the assertions below.
  shutdown_status = destroy ? termisu_destroy(handle) : termisu_close(handle)

  poll_thread.join
  shutdown_status.should eq(Termisu::FFI::Status::Ok.value)
  poll_status.get.should eq(Termisu::FFI::Status::Timeout.value)
ensure
  termisu_destroy(handle) if handle && handle != 0_u64
end

private def run_ffi_scheduler_close_scenario(scenario : String) : Nil
  context = Termisu::FFI::Context.new(sync_updates: false)

  case scenario
  when "in_flight"
    operation_started = Atomic(Bool).new(false)
    release_operation = Atomic(Bool).new(false)
    operation_finished = Atomic(Bool).new(false)

    spawn do
      context.with_operation do
        operation_started.set(true)
        until release_operation.get
          Fiber.yield
        end
      end
      operation_finished.set(true)
    end
    until operation_started.get
      Fiber.yield
    end

    spawn { release_operation.set(true) }
    context.close
    raise "in-flight operation fiber did not finish" unless operation_finished.get
  when "contended"
    operation_started = Atomic(Bool).new(false)
    release_operation = Atomic(Bool).new(false)
    winner_finished = Atomic(Bool).new(false)
    loser_finished = Atomic(Bool).new(false)

    spawn do
      context.with_operation do
        operation_started.set(true)
        until release_operation.get
          Fiber.yield
        end
      end
    end
    until operation_started.get
      Fiber.yield
    end

    spawn do
      context.close
      winner_finished.set(true)
    end
    while context.with_operation { true }
      Fiber.yield
    end

    # Queue the losing close ahead of the releaser. It must yield its fiber so
    # the operation and winning close can finish and publish @closed.
    spawn do
      context.close
      loser_finished.set(true)
    end
    spawn { release_operation.set(true) }

    until winner_finished.get && loser_finished.get
      Fiber.yield
    end
  else
    raise "unknown FFI scheduler close scenario: #{scenario}"
  end
ensure
  context.try &.close
end

private def assert_ffi_scheduler_close_completes(scenario : String) : Nil
  executable = Process.executable_path || fail("cannot locate the spec executable")
  process = Process.new(executable, ["--example", "__ffi_scheduler_close_child__"],
    env: {"TERMISU_FFI_SCHEDULER_CLOSE_SCENARIO" => scenario})
  finished = Channel(Process::Status).new
  spawn { finished.send(process.wait) }

  status = select
  when child_status = finished.receive
    child_status
  when timeout(3.seconds)
    process.signal(Signal::KILL)
    finished.receive
    fail "FFI scheduler close scenario #{scenario.inspect} timed out"
  end
  status.success?.should be_true
end

if scenario = ENV["TERMISU_FFI_SCHEDULER_CLOSE_SCENARIO"]?
  run_ffi_scheduler_close_scenario(scenario)
end

describe "Termisu C ABI" do
  it "exposes the expected ABI version" do
    termisu_abi_version.should eq(1_u32)
  end

  it "exposes a stable non-zero layout signature" do
    signature = termisu_layout_signature
    signature.should eq(Termisu::FFI::Layout.signature)
    signature.should_not eq(0_u64)
  end

  it "returns invalid handle status and populates last error" do
    termisu_clear_error
    termisu_destroy(0_u64).should eq(Termisu::FFI::Status::InvalidHandle.value)
    termisu_error_message.should contain("Invalid handle")
  end

  it "clears last error state explicitly" do
    termisu_destroy(0_u64).should eq(Termisu::FFI::Status::InvalidHandle.value)
    termisu_last_error_length.should be > 0_u64

    termisu_clear_error
    termisu_last_error_length.should eq(0_u64)
  end

  it "returns 0 when copying last error into a null buffer" do
    termisu_destroy(0_u64).should eq(Termisu::FFI::Status::InvalidHandle.value)
    termisu_last_error_length.should be > 0_u64
    termisu_last_error_copy(Pointer(UInt8).null, 16_u64).should eq(0_u64)
  end

  it "rejects null event pointer in poll_event" do
    termisu_clear_error
    status = termisu_poll_event(0_u64, 0, Pointer(Termisu::FFI::ABI::Event).null)
    status.should eq(Termisu::FFI::Status::InvalidArgument.value)
    termisu_error_message.should contain("out_event is null")
  end

  it "rejects invalid handle for set_cell" do
    style = default_ffi_style
    status = termisu_set_cell(9999_u64, 0, 0, 'A'.ord.to_u32, pointerof(style))
    status.should eq(Termisu::FFI::Status::InvalidHandle.value)
    termisu_error_message.should contain("Invalid handle")
  end

  it "rejects invalid handle for set_cells" do
    op = ffi_cell_op(0, 0, 'A'.ord)
    status = termisu_set_cells(9999_u64, pointerof(op), 1_u64)
    status.should eq(Termisu::FFI::Status::InvalidHandle.value)
    termisu_error_message.should contain("Invalid handle")
  end

  it "rejects null ops pointer in set_cells when count is positive" do
    termisu_clear_error
    status = termisu_set_cells(0_u64, Pointer(Termisu::FFI::ABI::CellOp).null, 1_u64)
    status.should eq(Termisu::FFI::Status::InvalidArgument.value)
    termisu_error_message.should contain("ops is null")
  end

  it "still validates the handle for an empty set_cells batch" do
    termisu_clear_error
    status = termisu_set_cells(0_u64, Pointer(Termisu::FFI::ABI::CellOp).null, 0_u64)
    status.should eq(Termisu::FFI::Status::InvalidHandle.value)
    termisu_error_message.should contain("Invalid handle")
  end

  it "supports core operations on a valid handle" do
    termisu_clear_error
    handle = termisu_create(1_u8)
    handle.should_not eq(0_u64)

    begin
      size = uninitialized Termisu::FFI::ABI::Size
      termisu_size(handle, pointerof(size)).should eq(Termisu::FFI::Status::Ok.value)
      size.width.should be >= 0
      size.height.should be >= 0

      termisu_sync_updates(handle).should eq(1_u8)
      termisu_set_sync_updates(handle, 0_u8).should eq(Termisu::FFI::Status::Ok.value)
      termisu_sync_updates(handle).should eq(0_u8)
      termisu_set_sync_updates(handle, 1_u8).should eq(Termisu::FFI::Status::Ok.value)
      termisu_sync_updates(handle).should eq(1_u8)

      termisu_clear(handle).should eq(Termisu::FFI::Status::Ok.value)
      termisu_render(handle).should eq(Termisu::FFI::Status::Ok.value)
      termisu_sync(handle).should eq(Termisu::FFI::Status::Ok.value)
      termisu_set_cursor(handle, 0, 0).should eq(Termisu::FFI::Status::Ok.value)
      termisu_hide_cursor(handle).should eq(Termisu::FFI::Status::Ok.value)
      termisu_show_cursor(handle).should eq(Termisu::FFI::Status::Ok.value)

      style = default_ffi_style
      in_bounds_status = termisu_set_cell(handle, 0, 0, 'A'.ord.to_u32, pointerof(style))
      if size.width > 0 && size.height > 0
        in_bounds_status.should eq(Termisu::FFI::Status::Ok.value)
      else
        in_bounds_status.should eq(Termisu::FFI::Status::Rejected.value)
        termisu_error_message.should contain("set_cell rejected")
      end

      rejected = termisu_set_cell(handle, size.width, 0, 'A'.ord.to_u32, pointerof(style))
      rejected.should eq(Termisu::FFI::Status::Rejected.value)
      termisu_error_message.should contain("set_cell rejected")

      if size.width > 0 && size.height > 0
        invalid_codepoint = termisu_set_cell(handle, 0, 0, 0x11_0000_u32, pointerof(style))
        invalid_codepoint.should eq(Termisu::FFI::Status::Error.value)
        termisu_error_message.should contain("Invalid Unicode codepoint")
      end

      ops = StaticArray[
        ffi_cell_op(0, 0, 'B'.ord),
        ffi_cell_op(1, 0, 'C'.ord),
      ]
      batch_status = termisu_set_cells(handle, ops.to_unsafe, ops.size.to_u64)
      if size.width > 1 && size.height > 0
        batch_status.should eq(Termisu::FFI::Status::Ok.value)
      else
        batch_status.should eq(Termisu::FFI::Status::Rejected.value)
        termisu_error_message.should contain("set_cells rejected")
      end

      mixed = StaticArray[
        ffi_cell_op(0, 0, 'D'.ord),
        ffi_cell_op(size.width, 0, 'E'.ord),
      ]
      mixed_status = termisu_set_cells(handle, mixed.to_unsafe, mixed.size.to_u64)
      mixed_status.should eq(Termisu::FFI::Status::Rejected.value)
      termisu_error_message.should contain("set_cells rejected")

      empty_status = termisu_set_cells(handle, Pointer(Termisu::FFI::ABI::CellOp).null, 0_u64)
      empty_status.should eq(Termisu::FFI::Status::Ok.value)

      # Codepoint validation raises before any bounds check, so these hold
      # regardless of the reported terminal size.
      bad = StaticArray[
        ffi_cell_op(0, 0, 'F'.ord),
        ffi_cell_op(0, 0, 0x11_0000),
      ]
      bad_status = termisu_set_cells(handle, bad.to_unsafe, bad.size.to_u64)
      bad_status.should eq(Termisu::FFI::Status::Error.value)
      termisu_error_message.should contain("Invalid Unicode codepoint")

      negative = StaticArray[ffi_cell_op(0, 0, -1)]
      negative_status = termisu_set_cells(handle, negative.to_unsafe, 1_u64)
      negative_status.should eq(Termisu::FFI::Status::Error.value)
      termisu_error_message.should contain("Invalid Unicode codepoint")

      termisu_enable_timer_ms(handle, 16).should eq(Termisu::FFI::Status::Ok.value)
      termisu_disable_timer(handle).should eq(Termisu::FFI::Status::Ok.value)
      termisu_enable_system_timer_ms(handle, 16).should eq(Termisu::FFI::Status::Ok.value)
      termisu_disable_timer(handle).should eq(Termisu::FFI::Status::Ok.value)

      termisu_enable_mouse(handle).should eq(Termisu::FFI::Status::Ok.value)
      termisu_disable_mouse(handle).should eq(Termisu::FFI::Status::Ok.value)
      termisu_enable_enhanced_keyboard(handle).should eq(Termisu::FFI::Status::Ok.value)
      termisu_disable_enhanced_keyboard(handle).should eq(Termisu::FFI::Status::Ok.value)

      # The three input modes and their queries. Without the queries a C or JS
      # caller can toggle a mode but never ask whether it is on, and shadowing the
      # state locally drifts the moment with_mode suspends and restores it.
      termisu_mouse_enabled(handle).should eq(0_u8)
      termisu_enable_mouse(handle).should eq(Termisu::FFI::Status::Ok.value)
      termisu_mouse_enabled(handle).should eq(1_u8)
      termisu_disable_mouse(handle).should eq(Termisu::FFI::Status::Ok.value)
      termisu_mouse_enabled(handle).should eq(0_u8)

      termisu_enhanced_keyboard(handle).should eq(0_u8)
      termisu_enable_enhanced_keyboard(handle).should eq(Termisu::FFI::Status::Ok.value)
      termisu_enhanced_keyboard(handle).should eq(1_u8)
      termisu_disable_enhanced_keyboard(handle).should eq(Termisu::FFI::Status::Ok.value)
      termisu_enhanced_keyboard(handle).should eq(0_u8)

      termisu_bracketed_paste(handle).should eq(0_u8)
      termisu_enable_bracketed_paste(handle).should eq(Termisu::FFI::Status::Ok.value)
      termisu_bracketed_paste(handle).should eq(1_u8)
      termisu_disable_bracketed_paste(handle).should eq(Termisu::FFI::Status::Ok.value)
      termisu_bracketed_paste(handle).should eq(0_u8)

      event = uninitialized Termisu::FFI::ABI::Event
      poll_status = termisu_poll_event(handle, 0, pointerof(event))
      valid_poll = [Termisu::FFI::Status::Ok.value, Termisu::FFI::Status::Timeout.value]
      valid_poll.should contain(poll_status)
    ensure
      termisu_destroy(handle)
    end
  end

  it "validates timer interval arguments" do
    handle = termisu_create(1_u8)
    handle.should_not eq(0_u64)

    begin
      termisu_enable_timer_ms(handle, 0).should eq(Termisu::FFI::Status::InvalidArgument.value)
      termisu_error_message.should contain("interval_ms must be > 0")

      termisu_enable_system_timer_ms(handle, -1).should eq(Termisu::FFI::Status::InvalidArgument.value)
      termisu_error_message.should contain("interval_ms must be > 0")
    ensure
      termisu_destroy(handle)
    end
  end

  it "closes and destroys handles idempotently" do
    handle = termisu_create(1_u8)
    handle.should_not eq(0_u64)

    termisu_close(handle).should eq(Termisu::FFI::Status::Ok.value)
    size = uninitialized Termisu::FFI::ABI::Size
    termisu_size(handle, pointerof(size)).should eq(Termisu::FFI::Status::InvalidHandle.value)
    termisu_destroy(handle).should eq(Termisu::FFI::Status::Ok.value)
    termisu_destroy(handle).should eq(Termisu::FFI::Status::InvalidHandle.value)
  end

  it "waits for in-flight FFI operations before releasing ownership" do
    handle = termisu_create(0_u8)
    handle.should_not eq(0_u64)
    context = Termisu::FFI::Registry.fetch(handle) || fail("created FFI context was not registered")

    operation_started = Atomic(Bool).new(false)
    release_operation = Atomic(Bool).new(false)
    operation_succeeded = Atomic(Bool).new(false)
    successor_attempt = Atomic(UInt64).new(UInt64::MAX)

    operation_thread = Thread.new do
      result = context.with_operation do |_leased|
        operation_started.set(true)
        until release_operation.get
          Thread.yield
        end
        true
      end
      operation_succeeded.set(result == true)
    end
    until operation_started.get
      Thread.yield
    end

    observer_thread = Thread.new do
      # Wait until destroy has closed the operation gate. Calls that fetched
      # the context before this point remain in its in-flight count.
      deadline = monotonic_now + 2.seconds
      while context.with_operation { true }
        raise "destroy did not begin closing the FFI context" if monotonic_now >= deadline
        Thread.yield
      end

      # Destroy must retain terminal ownership while the operation drains.
      successor_attempt.set(termisu_create(0_u8))
    ensure
      release_operation.set(true)
    end

    termisu_destroy(handle).should eq(Termisu::FFI::Status::Ok.value)
    operation_thread.join
    observer_thread.join
    operation_succeeded.get.should be_true
    successor_attempt.get.should eq(0_u64)

    size = uninitialized Termisu::FFI::ABI::Size
    termisu_size(handle, pointerof(size)).should eq(Termisu::FFI::Status::InvalidHandle.value)

    successor = termisu_create(0_u8)
    successor.should_not eq(0_u64)
    termisu_destroy(successor).should eq(Termisu::FFI::Status::Ok.value)
  ensure
    release_operation.try &.set(true)
    operation_thread.try &.join
    observer_thread.try &.join
    termisu_destroy(handle) if handle && handle != 0_u64
    termisu_destroy(successor) if successor && successor != 0_u64
  end

  it "lets same-scheduler operation fibers drain during close" do
    assert_ffi_scheduler_close_completes("in_flight")
  end

  it "lets same-scheduler close fibers complete when they contend" do
    assert_ffi_scheduler_close_completes("contended")
  end

  it "cancels real blocking C ABI polls before close and destroy drain operations" do
    assert_ffi_blocking_poll_cancelled(destroy: false)
    assert_ffi_blocking_poll_cancelled(destroy: true)
  end

  it "enforces terminal ownership across FFI handles" do
    first = termisu_create(0_u8)
    first.should_not eq(0_u64)

    termisu_create(0_u8).should eq(0_u64)
    termisu_error_message.should contain("already controlled")

    termisu_close(first).should eq(Termisu::FFI::Status::Ok.value)
    second = termisu_create(0_u8)
    second.should_not eq(0_u64)

    # Destroying the already-closed old handle cannot release the new owner.
    termisu_destroy(first).should eq(Termisu::FFI::Status::Ok.value)
    termisu_create(0_u8).should eq(0_u64)
    termisu_error_message.should contain("already controlled")

    termisu_destroy(second).should eq(Termisu::FFI::Status::Ok.value)
    third = termisu_create(0_u8)
    third.should_not eq(0_u64)
    termisu_destroy(third).should eq(Termisu::FFI::Status::Ok.value)
  ensure
    termisu_destroy(first) if first && first != 0_u64
    termisu_destroy(second) if second && second != 0_u64
    termisu_destroy(third) if third && third != 0_u64
  end

  it "truncates copied error messages safely" do
    termisu_clear_error
    termisu_destroy(0_u64).should eq(Termisu::FFI::Status::InvalidHandle.value)

    buffer = Bytes.new(4, 0_u8)
    copied = termisu_last_error_copy(buffer.to_unsafe, buffer.size.to_u64)
    copied.should eq(3_u64)
    String.new(buffer.to_unsafe).size.should be <= 3

    single = Bytes.new(1, 7_u8)
    termisu_last_error_copy(single.to_unsafe, 1_u64).should eq(0_u64)
    single[0].should eq(0_u8)
  end

  it "handles very large buffer lengths without overflow" do
    termisu_clear_error
    termisu_destroy(0_u64).should eq(Termisu::FFI::Status::InvalidHandle.value)

    len = termisu_last_error_length
    len.should be > 0_u64

    bytes = Bytes.new(len.to_i + 1, 0_u8)
    copied = termisu_last_error_copy(bytes.to_unsafe, UInt64::MAX)
    copied.should eq(len)
    String.new(bytes.to_unsafe).should contain("Invalid handle")
  end
end
