require "./poll"

# poll(2) compatibility for Darwin devices such as /dev/tty. Only readiness is
# observed: neither select(2) nor this adapter reads input or changes fd flags.
module Termisu::System::Readiness
  lib NativeSelect
    # Darwin's ordinary select wrapper rejects nfds > FD_SETSIZE even when the
    # caller supplies a larger bitmap. The unlimited symbol supports high fds.
    {% if flag?(:darwin) %}
      fun select = "select$DARWIN_EXTSN"(nfds : Int32, readfds : LibC::FdSet*, writefds : LibC::FdSet*,
                                         errorfds : LibC::FdSet*, timeout : LibC::Timeval*) : Int32
    {% else %}
      fun select(nfds : Int32, readfds : LibC::FdSet*, writefds : LibC::FdSet*,
                 errorfds : LibC::FdSet*, timeout : LibC::Timeval*) : Int32
    {% end %}
  end

  def self.poll(fds : Poll::Pollfd*, count : Poll::NfdsT, timeout_ms : Int32) : Int32
    result = Poll.poll(fds, count, timeout_ms)
    # Specs can exercise Darwin's valid-TTY POLLNVAL protocol on other hosts.
    {% if flag?(:darwin) || @top_level.has_constant?(:TERMISU_INPUT_READINESS_SPEC) %}
      if result > 0 && count.to_i.times.any? { |index| unsupported_terminal?(fds[index]) }
        return select_poll(fds, count, timeout_ms)
      end
    {% end %}
    result
  end

  # Also exercised directly on other Unix hosts, without emulating Darwin's ABI.
  def self.select_poll(fds : Poll::Pollfd*, count : Poll::NfdsT, timeout_ms : Int32) : Int32
    max_fd = -1
    count.to_i.times { |index| max_fd = {max_fd, fds[index].fd}.max }
    words = max_fd // 64 + 1
    readfds = Slice(UInt64).new(words, 0_u64)
    writefds = Slice(UInt64).new(words, 0_u64)
    count.to_i.times do |index|
      descriptor = fds[index]
      fd = descriptor.fd
      descriptor.revents = 0_i16
      fds[index] = descriptor
      next if fd < 0
      bit = 1_u64 << (fd % 64)
      readfds[fd // 64] |= bit if (fds[index].events & Poll::POLLIN) != 0
      writefds[fd // 64] |= bit if (fds[index].events & Poll::POLLOUT) != 0
    end

    timeout = uninitialized LibC::Timeval
    timeout.tv_sec = timeout_ms.to_i64 // 1000
    timeout.tv_usec = (timeout_ms.to_i64 % 1000) * 1000
    timeout_ptr = timeout_ms < 0 ? Pointer(LibC::Timeval).null : pointerof(timeout)
    result = NativeSelect.select(max_fd + 1, readfds.to_unsafe.as(LibC::FdSet*), writefds.to_unsafe.as(LibC::FdSet*),
      nil, timeout_ptr)
    return result if result <= 0

    # Preserve poll's HUP/ERR flags for pipes and sockets. Only discard NVAL for
    # descriptors select accepted that remain open (Darwin's unsupported devices).
    result = Poll.poll(fds, count, 0)
    return result if result < 0
    ready = 0
    count.to_i.times do |index|
      descriptor = fds[index]
      fd = descriptor.fd
      next if fd < 0
      descriptor.revents &= ~Poll::POLLNVAL if unsupported_terminal?(descriptor)
      bit = 1_u64 << (fd % 64)
      descriptor.revents |= Poll::POLLIN if (readfds[fd // 64] & bit) != 0
      descriptor.revents |= Poll::POLLOUT if (writefds[fd // 64] & bit) != 0
      fds[index] = descriptor
      ready += 1 if descriptor.revents != 0
    end
    ready
  end

  private def self.unsupported_terminal?(descriptor : Poll::Pollfd) : Bool
    (descriptor.revents & Poll::POLLNVAL) != 0 && LibC.isatty(descriptor.fd) == 1
  end
end
