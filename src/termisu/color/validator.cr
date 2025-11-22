# Color validation logic.
#
# Provides validation for color indices and parameters to ensure
# they fall within valid ranges for each color mode.
module Termisu::Color::Validator
  extend self

  # Validates ANSI-8 color index (0-7 or -1 for default).
  def validate_ansi8(index : Int32) : Nil
    unless index >= -1 && index <= 7
      raise ArgumentError.new("ANSI-8 index must be 0-7 or -1, got #{index}")
    end
  end

  # Validates ANSI-256 color index (0-255 or -1 for default).
  def validate_ansi256(index : Int32) : Nil
    unless index >= -1 && index <= 255
      raise ArgumentError.new("ANSI-256 index must be 0-255 or -1, got #{index}")
    end
  end

  # Validates grayscale level (0-23).
  def validate_grayscale(level : Int32) : Nil
    unless level >= 0 && level <= 23
      raise ArgumentError.new("Grayscale level must be 0-23, got #{level}")
    end
  end

  # Validates hex color string format (must be 6 characters).
  def validate_hex(hex : String) : Nil
    raise ArgumentError.new("Invalid hex color: #{hex}") unless hex.size == 6
  end
end
