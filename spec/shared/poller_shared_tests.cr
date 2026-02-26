# Shared test suite for Poller implementations.
#
# This macro generates a comprehensive test suite that validates
# any Poller implementation against the expected interface contract.
#
# Usage:
#   describe MyPoller do
#     poller_shared_tests(MyPoller)
#   end
macro poller_shared_tests(poller_class)
  describe "#add_timer" do
    it "creates a timer and returns handle" do
      poller = {{poller_class}}.new
      handle = poller.add_timer(100.milliseconds)

      handle.should be_a(Termisu::Event::Poller::TimerHandle)
      handle.id.should be >= 0_u64

      poller.close
    end

    it "creates multiple timers with unique handles" do
      poller = {{poller_class}}.new
      handle1 = poller.add_timer(100.milliseconds)
      handle2 = poller.add_timer(200.milliseconds)

      (handle1 == handle2).should be_false

      poller.close
    end

    it "raises after close" do
      poller = {{poller_class}}.new
      poller.close

      expect_raises(Exception, /closed/i) do
        poller.add_timer(100.milliseconds)
      end
    end
  end

  describe "#remove_timer" do
    it "removes an existing timer" do
      poller = {{poller_class}}.new
      handle = poller.add_timer(100.milliseconds)

      # Should not raise
      poller.remove_timer(handle)
      poller.close
    end

    it "is idempotent" do
      poller = {{poller_class}}.new
      handle = poller.add_timer(100.milliseconds)

      poller.remove_timer(handle)
      poller.remove_timer(handle) # Should not raise

      poller.close
    end
  end

  describe "#modify_timer" do
    it "modifies timer interval" do
      poller = {{poller_class}}.new
      handle = poller.add_timer(100.milliseconds)

      # Should not raise
      poller.modify_timer(handle, 50.milliseconds)

      poller.close
    end

    it "raises for invalid handle" do
      poller = {{poller_class}}.new
      invalid = Termisu::Event::Poller::TimerHandle.new(999_u64)

      expect_raises(ArgumentError) do
        poller.modify_timer(invalid, 100.milliseconds)
      end

      poller.close
    end
  end

  describe "#wait with timer" do
    it "returns timer event when timer expires" do
      poller = {{poller_class}}.new
      handle = poller.add_timer(10.milliseconds)

      result = poller.wait(100.milliseconds)

      result.should_not be_nil
      if r = result
        r.timer?.should be_true
        if th = r.timer_handle
          th.id.should eq(handle.id)
        end
        r.timer_expirations.should be >= 1_u64
      end

      poller.close
    end

    it "returns nil on timeout without events" do
      poller = {{poller_class}}.new
      # No timers, no fds

      result = poller.wait(10.milliseconds)

      result.should be_nil
      poller.close
    end

    it "handles repeating timers" do
      poller = {{poller_class}}.new
      poller.add_timer(5.milliseconds, repeating: true)

      # Should fire multiple times
      3.times do |i|
        result = poller.wait(50.milliseconds)
        result.should_not be_nil
        if r = result
          r.timer?.should be_true
        end
      end

      poller.close
    end

    it "handles one-shot timers" do
      poller = {{poller_class}}.new
      poller.add_timer(5.milliseconds, repeating: false)

      # First wait should get timer
      result1 = poller.wait(50.milliseconds)
      result1.should_not be_nil
      if r = result1
        r.timer?.should be_true
      end

      # Second wait should timeout (timer was one-shot)
      result2 = poller.wait(20.milliseconds)
      result2.should be_nil

      poller.close
    end
  end

  describe "fd lifecycle" do
    it "can register and unregister fds" do
      poller = {{poller_class}}.new

      reader, writer = IO.pipe

      poller.register_fd(reader.fd, Termisu::Event::Poller::FDEvents::Read)
      poller.unregister_fd(reader.fd)

      reader.close
      writer.close
      poller.close
    end

    it "detects readable fd" do
      poller = {{poller_class}}.new
      reader, writer = IO.pipe

      poller.register_fd(reader.fd, Termisu::Event::Poller::FDEvents::Read)

      writer.print("test")
      writer.flush

      result = poller.wait(100.milliseconds)

      result.should_not be_nil
      if r = result
        r.fd_readable?.should be_true
        r.fd.should eq(reader.fd)
      end

      reader.close
      writer.close
      poller.close
    end

    it "allows unregister then re-register of same fd" do
      poller = {{poller_class}}.new
      reader, writer = IO.pipe

      poller.register_fd(reader.fd, Termisu::Event::Poller::FDEvents::Read)
      poller.unregister_fd(reader.fd)
      poller.register_fd(reader.fd, Termisu::Event::Poller::FDEvents::Read)

      writer.print("test")
      writer.flush

      result = poller.wait(100.milliseconds)
      result.should_not be_nil
      if r = result
        r.fd_readable?.should be_true
        r.fd.should eq(reader.fd)
      end

      reader.close
      writer.close
      poller.close
    end
  end

  describe "#close" do
    it "is idempotent" do
      poller = {{poller_class}}.new

      poller.close
      poller.close # Should not raise
    end

    it "releases timers" do
      poller = {{poller_class}}.new
      poller.add_timer(100.milliseconds)
      poller.add_timer(200.milliseconds)

      # Should not leak resources
      poller.close
    end
  end
end
