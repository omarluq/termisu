# LibC bindings for kqueue on BSD systems (FreeBSD, OpenBSD).
#
# Crystal's stdlib only provides kqueue bindings for Darwin.
# This file provides cross-BSD kqueue support.
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
    # kqueue event filters
    EVFILT_READ   = -1_i16
    EVFILT_WRITE  = -2_i16
    EVFILT_TIMER  = -7_i16
    EVFILT_SIGNAL = -6_i16

    # kqueue event flags
    EV_ADD     = 0x0001_u16
    EV_DELETE  = 0x0002_u16
    EV_ENABLE  = 0x0004_u16
    EV_DISABLE = 0x0008_u16
    EV_ONESHOT = 0x0010_u16
    EV_CLEAR   = 0x0020_u16
    EV_EOF     = 0x8000_u16
    EV_ERROR   = 0x4000_u16

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
