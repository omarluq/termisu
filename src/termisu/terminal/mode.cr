# Terminal mode flags for controlling input behavior.
#
# Maps to POSIX termios local flags (c_lflag).
# Combine flags to create custom modes, or use preset methods.
#
# Standard Terminal Modes:
# | Mode     | ICANON | ECHO | ISIG | IEXTEN | Use Case                    |
# |----------|--------|------|------|--------|-----------------------------|
# | Raw      | OFF    | OFF  | OFF  | OFF    | Full TUI control            |
# | Cbreak   | OFF    | ON   | ON   | OFF    | Char-by-char with feedback  |
# | Cooked   | ON     | ON   | ON   | ON     | Shell-out, external programs|
# | Password | ON     | OFF  | ON   | OFF    | Secure text entry           |
# | SemiRaw  | OFF    | OFF  | ON   | OFF    | TUI with Ctrl+C support     |
#
# Example:
# ```
# # Using a preset mode
# mode = Termisu::Terminal::Mode.cooked
# mode.canonical? # => true
# mode.echo?      # => true
#
# # Custom mode: char-by-char with echo, no signals
# custom = Termisu::Terminal::Mode::Echo
# custom.echo?    # => true
# custom.signals? # => false
#
# # Combining flags
# mode = Termisu::Terminal::Mode::Canonical | Termisu::Terminal::Mode::Signals
# ```
@[Flags]
enum Termisu::Terminal::Mode
  # No special handling - raw character-by-character input.
  # Application receives every keystroke immediately.
  None = 0

  # Enable canonical (line-buffered) input mode.
  # Input is collected until Enter is pressed.
  # Terminal driver handles backspace, delete, line editing.
  # Maps to ICANON flag.
  Canonical = 1

  # Enable echo of typed characters to terminal.
  # Characters are displayed as the user types.
  # Maps to ECHO flag.
  Echo = 2

  # Enable signal generation from control characters.
  # Ctrl+C sends SIGINT, Ctrl+Z sends SIGTSTP, Ctrl+\ sends SIGQUIT.
  # Maps to ISIG flag.
  Signals = 4

  # Enable extended input processing.
  # Implementation-defined extensions (e.g., Ctrl+V literal next).
  # Maps to IEXTEN flag.
  Extended = 8

  # --- Preset Methods ---

  # Full raw mode - no terminal driver processing.
  # Application handles all input, no echo, no signals.
  # Use for: Full TUI applications (current Termisu default)
  def self.raw : self
    None
  end

  # Cbreak mode - character-by-character with feedback.
  # Each keystroke available immediately, with echo and signals.
  # Use for: Interactive prompts, char-by-char input with visual feedback
  def self.cbreak : self
    Echo | Signals
  end

  # Full cooked mode - standard terminal behavior.
  # Line buffering, echo, signals, extended processing.
  # Use for: Shell-out to external programs, REPL input
  def self.cooked : self
    Canonical | Echo | Signals | Extended
  end

  # Password mode - secure text entry.
  # Line buffering for editing, but no echo.
  # User can use backspace but characters aren't displayed.
  # Use for: Password prompts, sensitive input
  def self.password : self
    Canonical | Signals
  end

  # Semi-raw mode - raw with signal handling.
  # Character-by-character, no echo, but Ctrl+C works.
  # Use for: TUI that needs graceful Ctrl+C handling
  def self.semi_raw : self
    Signals
  end
end
