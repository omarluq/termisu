class Termisu::Terminfo
  @caps : Hash(String, String)

  def initialize
    name = ENV["TERM"]? || raise Termisu::Error.new("TERM environment variable not set")

    # Try to load capabilities from terminfo database first
    @caps = load_from_database(name)

    # Fill in any missing capabilities with builtins
    fill_missing_with_builtins(name)
  end

  # Load capabilities from terminfo database using name-based lookup
  private def load_from_database(term_name : String) : Hash(String, String)
    data = Database.new(term_name).load
    all_required = Capabilities::REQUIRED_FUNCS + Capabilities::REQUIRED_KEYS
    Parser.parse(data, all_required)
  rescue
    {} of String => String
  end

  # Fill in missing capabilities with builtin fallbacks
  private def fill_missing_with_builtins(term_name : String)
    builtin_funcs = Builtin.funcs_for(term_name)
    builtin_keys = Builtin.keys_for(term_name)

    # Fill missing funcs from builtins
    Capabilities::REQUIRED_FUNCS.each_with_index do |cap_name, idx|
      @caps[cap_name] = builtin_funcs[idx] unless @caps.has_key?(cap_name)
    end

    # Fill missing keys from builtins
    Capabilities::REQUIRED_KEYS.each_with_index do |cap_name, idx|
      @caps[cap_name] = builtin_keys[idx] unless @caps.has_key?(cap_name)
    end
  end

  # Get capability value by name with fallback to empty string
  private def get_cap(name : String) : String
    @caps.fetch(name, "")
  end

  # Convenience accessors using capability names
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
