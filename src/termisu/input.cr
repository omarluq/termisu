# Input module for terminal event handling.
#
# Provides key and modifier types, and the Input::Parser
# for parsing raw terminal input into structured Event objects.
#
# This module builds on top of the existing Reader infrastructure,
# transforming raw bytes into high-level Event objects.
module Termisu::Input
end

require "./input/*"
