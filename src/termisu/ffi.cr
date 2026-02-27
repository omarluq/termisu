# C ABI bridge for non-Crystal integrations.
#
# Exposes stable C symbols, opaque handles, flat structs, and explicit
# status/error handling for FFI callers.
module Termisu::FFI
end

require "./ffi/version"
require "./ffi/status"
require "./ffi/event_type"
require "./ffi/color_mode"
require "./ffi/abi"
require "./ffi/context"
require "./ffi/error_state"
require "./ffi/registry"
require "./ffi/runtime"
require "./ffi/guards"
require "./ffi/conversions"
require "./ffi/core"
require "./ffi/exports"
