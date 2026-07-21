# C ABI bridge for non-Crystal integrations.
#
# Exposes stable C symbols, opaque handles, flat structs, and explicit
# status/error handling for FFI callers.
#
# Lives at ffi/ffi.cr (not termisu/ffi.cr) so the `require "./termisu/*"`
# glob in src/termisu.cr cannot reach it - plain `require "termisu"`
# consumers must not link the exported C symbols. Build src/termisu_ffi.cr
# to produce libtermisu.
module Termisu::FFI
end

require "./version"
require "./status"
require "./event_type"
require "./color_mode"
require "./abi"
require "./layout"
require "./context"
require "./error_state"
require "./registry"
require "./runtime"
require "./guards"
require "./conversions"
require "./core"
require "./exports"
