# Entry point for the Termisu C ABI shared library (libtermisu).
#
# The FFI layer is intentionally excluded from src/termisu.cr's glob so that
# plain `require "termisu"` consumers do not link the exported C symbols.
# Build this file instead of src/termisu.cr to produce libtermisu.
require "./termisu"
require "./termisu/ffi"
