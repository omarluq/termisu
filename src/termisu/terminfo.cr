# Terminfo database interface for terminal capability management.
#
# Provides access to terminal control sequences by loading capabilities from
# the system terminfo database with fallback to hardcoded values for common
# terminals (xterm, linux).
#
# ## Loading Strategy
#
# 1. Attempts to load capabilities from terminfo database at standard locations
# 2. Falls back to built-in escape sequences for xterm/linux if database unavailable
# 3. Merges database values with builtins, preferring database values
#
# ## Usage
#
# ```
# terminfo = Termisu::Terminfo.new
# puts terminfo.clear_screen # => "\e[H\e[2J"
# puts terminfo.bold         # => "\e[1m"
# ```
class Termisu::Terminfo
  @caps : Hash(String, String)

  def initialize
    term_name = ENV["TERM"]? || raise Termisu::Error.new("TERM environment variable not set")

    @caps = load_from_database(term_name)
    fill_missing_with_builtins(term_name)
  end

  # Loads capabilities from the terminfo database.
  #
  # Attempts to locate and parse the terminfo file for the given terminal,
  # extracting all required function and key capabilities.
  #
  # Returns empty hash if database is unavailable or parsing fails.
  private def load_from_database(term_name : String) : Hash(String, String)
    data = Database.new(term_name).load
    required = Capabilities::REQUIRED_FUNCS + Capabilities::REQUIRED_KEYS
    Parser.parse(data, required)
  rescue
    {} of String => String
  end

  # Fills in missing capabilities with hardcoded fallback values.
  #
  # Uses built-in escape sequences for xterm and linux terminals to ensure
  # basic functionality even when terminfo database is unavailable.
  private def fill_missing_with_builtins(term_name : String)
    fill_capability_group(Capabilities::REQUIRED_FUNCS, Builtin.funcs_for(term_name))
    fill_capability_group(Capabilities::REQUIRED_KEYS, Builtin.keys_for(term_name))
  end

  # Fills missing capabilities from a builtin array.
  private def fill_capability_group(names : Array(String), values : Array(String))
    names.each_with_index do |cap_name, idx|
      @caps[cap_name] ||= values[idx]
    end
  end

  # Retrieves a capability value by name.
  #
  # Returns empty string if capability is not found.
  private def get_cap(name : String) : String
    @caps.fetch(name, "")
  end

  # Terminal Control Capabilities
  #
  # The following methods provide access to terminal control sequences
  # for screen management, cursor control, and text attributes.
  def enter_ca : String
    get_cap("smcup")
  end

  def exit_ca : String
    get_cap("rmcup")
  end

  def show_cursor : String
    get_cap("cnorm")
  end

  def hide_cursor : String
    get_cap("civis")
  end

  def clear_screen : String
    get_cap("clear")
  end

  def sgr0 : String
    get_cap("sgr0")
  end

  def underline : String
    get_cap("smul")
  end

  def bold : String
    get_cap("bold")
  end

  def blink : String
    get_cap("blink")
  end

  def reverse : String
    get_cap("rev")
  end

  def enter_keypad : String
    get_cap("smkx")
  end

  def exit_keypad : String
    get_cap("rmkx")
  end
end

require "./terminfo/*"
