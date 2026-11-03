require "../../spec_helper"
require "../../../src/termisu/system/readiness"

{% if flag?(:linux) %}
  require "c/sys/resource"
{% end %}

private def readiness_pollfd(fd : Int32, events : Int16 = Termisu::System::Poll::POLLIN)
  descriptor = uninitialized Termisu::System::Poll::Pollfd
  descriptor.fd = fd
  descriptor.events = events
  descriptor.revents = 0_i16
  descriptor
end

describe Termisu::System::Readiness do
  it "waits for the control descriptor without consuming input or changing flags" do
    input_fd, input_writer = create_pipe
    control_fd, control_writer = create_pipe
    descriptors = StaticArray[readiness_pollfd(control_fd), readiness_pollfd(input_fd)]
    flags = LibC.fcntl(input_fd, LibC::F_GETFL, 0)
    result = 0
    worker = Thread.new do
      result = Termisu::System::Readiness.select_poll(descriptors.to_unsafe,
        Termisu::System::Poll::NfdsT.new(2), 250)
    end
    sleep 5.milliseconds
    LibC.write(control_writer, "c".to_unsafe, 1).should eq(1)
    worker.join

    result.should eq(1)
    descriptors[0].revents.should eq(Termisu::System::Poll::POLLIN)
    descriptors[1].revents.should eq(0)
    LibC.fcntl(input_fd, LibC::F_GETFL, 0).should eq(flags)
    byte = uninitialized UInt8
    LibC.read(control_fd, pointerof(byte), 1).should eq(1)
    byte.should eq('c'.ord)
  ensure
    worker.try(&.join)
    LibC.close(input_fd) if input_fd
    LibC.close(input_writer) if input_writer
    LibC.close(control_fd) if control_fd
    LibC.close(control_writer) if control_writer
  end

  it "retains HUP while leaving the trailing input unread" do
    read_fd, write_fd = create_pipe
    descriptor = readiness_pollfd(read_fd)
    LibC.write(write_fd, "a".to_unsafe, 1).should eq(1)
    LibC.close(write_fd)
    write_fd = -1

    Termisu::System::Readiness.select_poll(pointerof(descriptor),
      Termisu::System::Poll::NfdsT.new(1), 0).should eq(1)
    (descriptor.revents & Termisu::System::Poll::POLLHUP).should_not eq(0)
    byte = uninitialized UInt8
    LibC.read(read_fd, pointerof(byte), 1).should eq(1)
    byte.should eq('a'.ord)
  ensure
    LibC.close(read_fd) if read_fd
    LibC.close(write_fd) if write_fd && write_fd >= 0
  end

  it "preserves the real EBADF from select for closed descriptors" do
    read_fd, write_fd = create_pipe
    descriptor = readiness_pollfd(read_fd)
    LibC.close(read_fd)

    result = Termisu::System::Readiness.select_poll(pointerof(descriptor),
      Termisu::System::Poll::NfdsT.new(1), 0)
    errno = Errno.value
    result.should eq(-1)
    errno.should eq(Errno::EBADF)
  ensure
    LibC.close(write_fd) if write_fd
  end

  it "accepts a valid controlling TTY without masking invalid descriptors or changing flags" do
    tty = Termisu::TTY.new
    flags = LibC.fcntl(tty.infd, LibC::F_GETFL, 0)
    LibC.fcntl(tty.infd, LibC::F_GETFD, 0).should be >= 0
    descriptor = readiness_pollfd(tty.infd)

    Termisu::System::Readiness.poll(pointerof(descriptor),
      Termisu::System::Poll::NfdsT.new(1), 0).should be >= 0
    (descriptor.revents & Termisu::System::Poll::POLLNVAL).should eq(0)
    LibC.fcntl(tty.infd, LibC::F_GETFL, 0).should eq(flags)
  ensure
    tty.try(&.close)
  end

  it "does not turn invalid descriptors into Darwin device readiness" do
    read_fd, write_fd = create_pipe
    descriptor = readiness_pollfd(read_fd)
    LibC.close(read_fd)

    Termisu::System::Readiness.poll(pointerof(descriptor),
      Termisu::System::Poll::NfdsT.new(1), 0).should eq(1)
    descriptor.revents.should eq(Termisu::System::Poll::POLLNVAL)
  ensure
    LibC.close(write_fd) if write_fd
  end

  it "reports timeout without stale event flags" do
    read_fd, write_fd = create_pipe
    descriptor = readiness_pollfd(read_fd)
    descriptor.revents = Termisu::System::Poll::POLLNVAL

    Termisu::System::Readiness.select_poll(pointerof(descriptor),
      Termisu::System::Poll::NfdsT.new(1), 0).should eq(0)
    descriptor.revents.should eq(0)
  ensure
    LibC.close(read_fd) if read_fd
    LibC.close(write_fd) if write_fd
  end

  {% if flag?(:linux) %}
    it "sizes select bitmaps for real descriptors above FD_SETSIZE" do
      min_fd = Termisu::Reader::FD_SETSIZE + 64
      limit = uninitialized LibC::Rlimit
      LibC.getrlimit(LibC::RLIMIT_NOFILE, pointerof(limit)).should eq(0)
      if limit.rlim_cur <= min_fd
        pending!("RLIMIT_NOFILE=#{limit.rlim_cur} cannot allocate fd >= #{min_fd}")
      end

      read_fd, write_fd = create_pipe
      high_fd = LibC.fcntl(read_fd, 0, min_fd)
      high_fd.should be >= Termisu::Reader::FD_SETSIZE
      descriptor = readiness_pollfd(high_fd)
      LibC.write(write_fd, "h".to_unsafe, 1).should eq(1)

      Termisu::System::Readiness.select_poll(pointerof(descriptor),
        Termisu::System::Poll::NfdsT.new(1), 0).should eq(1)
      descriptor.revents.should eq(Termisu::System::Poll::POLLIN)
    ensure
      LibC.close(high_fd) if high_fd && high_fd >= 0
      LibC.close(read_fd) if read_fd
      LibC.close(write_fd) if write_fd
    end
  {% end %}
end
