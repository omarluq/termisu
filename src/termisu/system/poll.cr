# Internal poll(2) bindings owned by Termisu.
#
# Keeping these declarations out of the global LibC namespace avoids
# shard-to-shard collisions when other dependencies patch missing poll
# bindings too.
module Termisu::System
  lib Poll
    struct Pollfd
      fd : Int32
      events : Int16
      revents : Int16
    end

    # nfds_t maps to unsigned long on supported Termisu targets.
    alias NfdsT = LibC::ULong

    fun poll(fds : Pollfd*, nfds : NfdsT, timeout : Int32) : Int32

    POLLIN   = 0x0001_i16
    POLLOUT  = 0x0004_i16
    POLLERR  = 0x0008_i16
    POLLHUP  = 0x0010_i16
    POLLNVAL = 0x0020_i16
  end
end
