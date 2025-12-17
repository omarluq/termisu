# LibC bindings for kqueue on BSD systems (FreeBSD, OpenBSD).
#
# Crystal's stdlib provides kqueue constants (EVFILT_*, EV_*) and the
# Kevent struct, but not the kqueue/kevent functions for FreeBSD/OpenBSD.

{% if flag?(:freebsd) || flag?(:openbsd) %}
  lib LibC
    # Create a new kernel event queue
    fun kqueue : Int32

    # Register events / wait for events
    fun kevent(
      kq : Int32,
      changelist : Kevent*,
      nchanges : Int32,
      eventlist : Kevent*,
      nevents : Int32,
      timeout : Timespec*,
    ) : Int32
  end
{% end %}
