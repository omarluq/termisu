# LibC bindings for kqueue on BSD systems (FreeBSD, OpenBSD).
#
# Crystal's stdlib provides kqueue constants (EVFILT_*, EV_*) but not
# the kqueue/kevent functions or Kevent struct for FreeBSD/OpenBSD.
#
# FreeBSD kevent struct (from sys/event.h):
#   uintptr_t ident     - identifier for this event
#   short     filter    - filter for event
#   u_short   flags     - action flags for kqueue
#   u_int     fflags    - filter flag value
#   intptr_t  data      - filter data value
#   void*     udata     - opaque user data identifier

{% if flag?(:freebsd) || flag?(:openbsd) %}
  lib LibC
    # kevent structure - matches FreeBSD sys/event.h
    struct Kevent
      ident : SizeT   # uintptr_t - identifier for this event
      filter : Int16  # short - filter for event
      flags : UInt16  # u_short - action flags for kqueue
      fflags : UInt32 # u_int - filter flag value
      data : SSizeT   # intptr_t - filter data value
      udata : Void*   # opaque user data identifier
    end

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
