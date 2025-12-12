# Text attributes for terminal cells.
#
# Attributes can be combined using bitwise OR (|).
# Multiple attributes are supported, but only one color can be set per foreground/background.
#
# Example:
# ```
# attr = Termisu::Attribute::Bold | Termisu::Attribute::Underline
# ```
@[Flags]
enum Termisu::Attribute : UInt16
  # No attributes
  None = 0

  # Bold/bright text
  Bold = 1

  # Underlined text (not supported on all terminals)
  Underline = 2

  # Reverse video (swap fg/bg colors)
  Reverse = 4

  # Blinking text
  Blink = 8

  # Dim/faint text
  Dim = 16

  # Italic/cursive text (not supported on all terminals)
  Cursive = 32

  # Alias for Cursive (more common name)
  Italic = 32

  # Hidden/invisible text
  Hidden = 64

  # Strikethrough text (crossed-out)
  Strikethrough = 128
end
