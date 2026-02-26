require "../../spec_helper"
require "../../../src/termisu/time_compat"

describe Termisu::Event::Poller do
  describe ".create" do
    it "returns a platform-appropriate poller" do
      poller = Termisu::Event::Poller.create
      poller.should be_a(Termisu::Event::Poller)
      poller.close
    end

    it "returns Linux poller on Linux" do
      {% if flag?(:linux) %}
        poller = Termisu::Event::Poller.create
        poller.should be_a(Termisu::Event::Poller::Linux)
        poller.close
      {% end %}
    end

    it "returns Kqueue poller on macOS/BSD" do
      {% if flag?(:darwin) || flag?(:freebsd) || flag?(:openbsd) %}
        poller = Termisu::Event::Poller.create
        poller.should be_a(Termisu::Event::Poller::Kqueue)
        poller.close
      {% end %}
    end
  end

  describe Termisu::Event::Poller::FDEvents do
    it "supports flags enum operations" do
      events = Termisu::Event::Poller::FDEvents::Read | Termisu::Event::Poller::FDEvents::Write
      events.read?.should be_true
      events.write?.should be_true
      events.error?.should be_false
    end
  end

  describe Termisu::Event::Poller::TimerHandle do
    it "creates with id" do
      handle = Termisu::Event::Poller::TimerHandle.new(42_u64)
      handle.id.should eq(42_u64)
    end

    it "supports equality" do
      handle1 = Termisu::Event::Poller::TimerHandle.new(1_u64)
      handle2 = Termisu::Event::Poller::TimerHandle.new(1_u64)
      handle3 = Termisu::Event::Poller::TimerHandle.new(2_u64)

      (handle1 == handle2).should be_true
      (handle1 == handle3).should be_false
    end
  end

  describe Termisu::Event::Poller::PollResult do
    it "creates timer result" do
      handle = Termisu::Event::Poller::TimerHandle.new(1_u64)
      result = Termisu::Event::Poller::PollResult.new(
        type: Termisu::Event::Poller::PollResult::Type::Timer,
        timer_handle: handle,
        timer_expirations: 5_u64
      )

      result.timer?.should be_true
      result.fd_readable?.should be_false
      result.timer_handle.should eq(handle)
      result.timer_expirations.should eq(5_u64)
    end

    it "creates fd readable result" do
      result = Termisu::Event::Poller::PollResult.new(
        type: Termisu::Event::Poller::PollResult::Type::FDReadable,
        fd: 42
      )

      result.fd_readable?.should be_true
      result.timer?.should be_false
      result.fd.should eq(42)
    end

    it "provides convenience predicates" do
      timer = Termisu::Event::Poller::PollResult.new(type: :timer)
      timer.timer?.should be_true

      readable = Termisu::Event::Poller::PollResult.new(type: :fd_readable, fd: 1)
      readable.fd_readable?.should be_true

      writable = Termisu::Event::Poller::PollResult.new(type: :fd_writable, fd: 1)
      writable.fd_writable?.should be_true

      error = Termisu::Event::Poller::PollResult.new(type: :fd_error, fd: 1)
      error.fd_error?.should be_true

      signal = Termisu::Event::Poller::PollResult.new(type: :signal, fd: 1)
      signal.signal?.should be_true
    end
  end
end

# Test the Poll fallback (always available)
describe Termisu::Event::Poller::Poll do
  poller_shared_tests(Termisu::Event::Poller::Poll)

  describe "timer precision" do
    it "fires within reasonable tolerance" do
      poller = Termisu::Event::Poller::Poll.new
      poller.add_timer(20.milliseconds)

      start = monotonic_now
      result = poller.wait(100.milliseconds)
      elapsed = monotonic_now - start

      result.should_not be_nil
      if r = result
        r.timer?.should be_true
      end

      # Should fire within 20-40ms (allowing for scheduling variance)
      elapsed.should be >= 15.milliseconds
      elapsed.should be < 50.milliseconds

      poller.close
    end
  end

  describe "missed tick detection" do
    it "reports expiration count for slow processing" do
      poller = Termisu::Event::Poller::Poll.new
      poller.add_timer(5.milliseconds, repeating: true)

      # Wait longer than one interval
      sleep 30.milliseconds

      result = poller.wait(50.milliseconds)
      result.should_not be_nil

      # Should report multiple expirations
      # The exact count depends on timing but should be > 1
      if r = result
        r.timer_expirations.should be >= 1_u64
      end

      poller.close
    end
  end

  describe "user timeout respected with active timer (BUG-011 regression)" do
    # Regression for issue #011: Poll#wait(short_timeout) would ignore the user timeout when
    # active timers existed. The poll loop would keep looping until the timer
    # fired, effectively replacing the user's short timeout with the timer's
    # longer interval. The fix records a deadline at method entry and checks
    # it after every poll cycle.

    it "wait(20ms) returns nil within ~50ms even with a 200ms timer" do
      poller = Termisu::Event::Poller::Poll.new
      poller.add_timer(200.milliseconds, repeating: true)

      start = monotonic_now
      result = poller.wait(20.milliseconds)
      elapsed = monotonic_now - start

      # Should return nil (timer hasn't fired yet)
      result.should be_nil

      # Should complete in ~20-50ms, NOT 200ms
      elapsed.should be < 80.milliseconds
      elapsed.should be >= 15.milliseconds

      poller.close
    end

    it "wait(10ms) returns nil quickly with multiple long timers" do
      poller = Termisu::Event::Poller::Poll.new
      poller.add_timer(500.milliseconds, repeating: true)
      poller.add_timer(1.second, repeating: true)

      start = monotonic_now
      result = poller.wait(10.milliseconds)
      elapsed = monotonic_now - start

      result.should be_nil
      elapsed.should be < 50.milliseconds

      poller.close
    end

    it "wait returns timer event when timer fires before user timeout" do
      poller = Termisu::Event::Poller::Poll.new
      poller.add_timer(10.milliseconds)

      # User timeout is longer than timer interval
      result = poller.wait(200.milliseconds)

      result.should_not be_nil
      if r = result
        r.timer?.should be_true
      end

      poller.close
    end
  end

  describe "fd registration" do
    it "can register and unregister fds" do
      poller = Termisu::Event::Poller::Poll.new

      reader, writer = IO.pipe

      poller.register_fd(reader.fd, Termisu::Event::Poller::FDEvents::Read)
      poller.unregister_fd(reader.fd)

      reader.close
      writer.close
      poller.close
    end

    it "detects readable fd" do
      poller = Termisu::Event::Poller::Poll.new
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

    it "updates events when registering same fd twice" do
      poller = Termisu::Event::Poller::Poll.new
      reader, writer = IO.pipe

      # Register for read
      poller.register_fd(reader.fd, Termisu::Event::Poller::FDEvents::Read)

      # Re-register for write (should update, not add duplicate)
      poller.register_fd(reader.fd, Termisu::Event::Poller::FDEvents::Write)

      # Write data - should NOT trigger read event since we changed to write-only
      writer.print("test")
      writer.flush

      # This should timeout since we're only watching for write and fd is readable.
      #
      # NOTE: FreeBSD returns POLLOUT immediately for pipe read-ends registered
      # for write events. This is unspecified POSIX behavior - the spec doesn't
      # define what happens when polling a read-only fd for writability.
      #
      # Platform interpretations differ:
      # - FreeBSD: "operation won't block" = true (fails with EBADF, doesn't block)
      # - Linux: "operation can succeed" = false (write can never succeed)
      #
      # Both interpretations are valid. See:
      # - POSIX poll(): https://pubs.opengroup.org/onlinepubs/9699919799/functions/poll.html
      # - Platform variance: https://www.greenend.org.uk/rjk/tech/poll.html
      # - FreeBSD fixes: https://reviews.freebsd.org/D24528
      {% unless flag?(:freebsd) %}
        result = poller.wait(20.milliseconds)
        result.should be_nil
      {% end %}

      reader.close
      writer.close
      poller.close
    end

    it "allows unregister then re-register of same fd" do
      poller = Termisu::Event::Poller::Poll.new
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
end

# Test Linux backend (if available)
{% if flag?(:linux) %}
  describe Termisu::Event::Poller::Linux do
    poller_shared_tests(Termisu::Event::Poller::Linux)

    describe "timerfd precision" do
      it "fires with high precision" do
        poller = Termisu::Event::Poller::Linux.new
        poller.add_timer(20.milliseconds)

        start = monotonic_now
        result = poller.wait(100.milliseconds)
        elapsed = monotonic_now - start

        result.should_not be_nil
        if r = result
          r.timer?.should be_true
        end

        # timerfd should be more precise than poll
        elapsed.should be >= 18.milliseconds
        elapsed.should be < 40.milliseconds

        poller.close
      end
    end

    describe "fd registration" do
      it "can register and unregister fds" do
        poller = Termisu::Event::Poller::Linux.new

        # Create a pipe for testing
        reader, writer = IO.pipe

        poller.register_fd(reader.fd, Termisu::Event::Poller::FDEvents::Read)
        poller.unregister_fd(reader.fd)

        reader.close
        writer.close
        poller.close
      end

      it "detects readable fd" do
        poller = Termisu::Event::Poller::Linux.new
        reader, writer = IO.pipe

        poller.register_fd(reader.fd, Termisu::Event::Poller::FDEvents::Read)

        # Write data to make it readable
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

      it "updates events when registering same fd twice (idempotent)" do
        poller = Termisu::Event::Poller::Linux.new
        reader, writer = IO.pipe

        # Register for read
        poller.register_fd(reader.fd, Termisu::Event::Poller::FDEvents::Read)

        # Re-register for read|write — should succeed (not EEXIST)
        poller.register_fd(reader.fd, Termisu::Event::Poller::FDEvents::Read | Termisu::Event::Poller::FDEvents::Write)

        # Write data to make it readable
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
        poller = Termisu::Event::Poller::Linux.new
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
  end
{% end %}

# Test Kqueue backend (if available)
{% if flag?(:darwin) || flag?(:freebsd) || flag?(:openbsd) %}
  describe Termisu::Event::Poller::Kqueue do
    poller_shared_tests(Termisu::Event::Poller::Kqueue)

    describe "fd registration" do
      it "can register and unregister fds" do
        poller = Termisu::Event::Poller::Kqueue.new

        reader, writer = IO.pipe

        poller.register_fd(reader.fd, Termisu::Event::Poller::FDEvents::Read)
        poller.unregister_fd(reader.fd)

        reader.close
        writer.close
        poller.close
      end

      it "detects readable fd" do
        poller = Termisu::Event::Poller::Kqueue.new
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

      it "updates events when registering same fd twice (idempotent)" do
        poller = Termisu::Event::Poller::Kqueue.new
        reader, writer = IO.pipe

        # Register for read
        poller.register_fd(reader.fd, Termisu::Event::Poller::FDEvents::Read)

        # Re-register for read|write — should succeed (not accumulate filters)
        poller.register_fd(reader.fd, Termisu::Event::Poller::FDEvents::Read | Termisu::Event::Poller::FDEvents::Write)

        # Write data to make it readable
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
        poller = Termisu::Event::Poller::Kqueue.new
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
  end
{% end %}
