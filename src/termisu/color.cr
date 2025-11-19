# Terminal colors.
#
# Supports basic 8 ANSI colors (0-7) with named constants.
# Extended 256-color and RGB support will be added in future versions.
#
# Example:
# ```
# cell = Termisu::Cell.new('A', fg: Color::Red, bg: Color::Black)
# ```
enum Termisu::Color : Int32
  # Basic 8 ANSI colors (0-7)
  Black   = 0
  Red     = 1
  Green   = 2
  Yellow  = 3
  Blue    = 4
  Magenta = 5
  Cyan    = 6
  White   = 7

  # Default terminal colors (let terminal decide)
  Default = -1

  # Future: 256-color palette (8-255)
  # Future: RGB/Truecolor support
end
