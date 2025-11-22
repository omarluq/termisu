# Color palette and named color factories.
#
# Provides convenient access to standard ANSI colors through both
# constant and method-style APIs.
module Termisu::Color::Palette
  extend self

  # Named color data: maps names to ANSI-256 indices
  BASIC_COLORS = {
    black:   0,
    red:     1,
    green:   2,
    yellow:  3,
    blue:    4,
    magenta: 5,
    cyan:    6,
    white:   7,
  }

  BRIGHT_COLORS = {
    bright_black:   8,
    bright_red:     9,
    bright_green:   10,
    bright_yellow:  11,
    bright_blue:    12,
    bright_magenta: 13,
    bright_cyan:    14,
    bright_white:   15,
  }

  # Creates a named basic color.
  def basic_color(name : Symbol) : Termisu::Color
    index = BASIC_COLORS.fetch(name) { raise ArgumentError.new("Unknown color: #{name}") }
    Termisu::Color.ansi8(index)
  end

  # Creates a named bright color.
  def bright_color(name : Symbol) : Termisu::Color
    index = BRIGHT_COLORS.fetch(name) { raise ArgumentError.new("Unknown bright color: #{name}") }
    Termisu::Color.ansi256(index)
  end

  # Creates a grayscale color from level (0-23).
  def grayscale_color(level : Int32) : Termisu::Color
    Validator.validate_grayscale(level)
    Termisu::Color.ansi256(232 + level)
  end
end
