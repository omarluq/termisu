# Color string formatting and representation.
#
# Provides string conversion methods for different color modes.
module Termisu::Color::Formatters
  extend self

  # Formats a color as a string representation.
  def to_s(color : Termisu::Color, io : IO) : Nil
    case color.mode
    when .ansi8?
      io << "ANSI8(#{color.index})"
    when .ansi256?
      io << "ANSI256(#{color.index})"
    when .rgb?
      io << "RGB(#{color.r}, #{color.g}, #{color.b})"
    end
  end
end
