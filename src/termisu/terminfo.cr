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
# puts terminfo.clear_screen_seq # => "\e[H\e[2J"
# puts terminfo.bold_seq         # => "\e[1m"
# ```
#
# Note: All capability methods return escape sequence STRINGS, not actions.
# The `_seq` suffix indicates this clearly.
class Termisu::Terminfo
  Log = Termisu::Logs::Terminfo
  @caps : Hash(String, String)

  # Cached capability strings for frequently-used parametrized capabilities.
  # These avoid repeated hash lookups during rendering.
  @cached_cup : String?
  @cached_setaf : String?
  @cached_setab : String?
  @cached_cuf : String?
  @cached_cub : String?
  @cached_cuu : String?
  @cached_cud : String?
  @cached_hpa : String?
  @cached_vpa : String?
  @cached_ech : String?
  @cached_il : String?
  @cached_dl : String?

  def initialize
    term_name = ENV["TERM"]? || raise Termisu::Error.new("TERM environment variable not set")
    Log.info { "Loading terminfo for TERM=#{term_name}" }

    @caps = load_from_database(term_name)
    fill_missing_with_builtins(term_name)
    cache_frequent_capabilities
    Log.debug { "Loaded #{@caps.size} capabilities" }
  end

  # Pre-caches frequently-used parametrized capability strings.
  private def cache_frequent_capabilities
    @cached_cup = get_cap("cup")
    @cached_setaf = get_cap("setaf")
    @cached_setab = get_cap("setab")
    @cached_cuf = get_cap("cuf")
    @cached_cub = get_cap("cub")
    @cached_cuu = get_cap("cuu")
    @cached_cud = get_cap("cud")
    @cached_hpa = get_cap("hpa")
    @cached_vpa = get_cap("vpa")
    @cached_ech = get_cap("ech")
    @cached_il = get_cap("il")
    @cached_dl = get_cap("dl")
  end

  # Loads capabilities from the terminfo database.
  private def load_from_database(term_name : String) : Hash(String, String)
    data = Database.new(term_name).load
    required = Capabilities::REQUIRED_FUNCS + Capabilities::REQUIRED_KEYS
    caps = Parser.parse(data, required)
    Log.debug { "Loaded #{caps.size} capabilities from database" }
    caps
  rescue ex
    Log.warn { "Failed to load terminfo database: #{ex.message}" }
    {} of String => String
  end

  # Fills in missing capabilities with hardcoded fallback values.
  private def fill_missing_with_builtins(term_name : String)
    before_count = @caps.size
    fill_capability_group(Capabilities::REQUIRED_FUNCS, Builtin.funcs_for(term_name))
    fill_capability_group(Capabilities::REQUIRED_KEYS, Builtin.keys_for(term_name))
    added = @caps.size - before_count
    Log.debug { "Filled #{added} missing capabilities from builtins" } if added > 0
  end

  # Fills missing capabilities from a builtin array.
  private def fill_capability_group(names : Array(String), values : Array(String))
    names.each_with_index do |cap_name, idx|
      @caps[cap_name] ||= values[idx]
    end
  end

  # Retrieves a capability value by name.
  private def get_cap(name : String) : String
    @caps.fetch(name, "")
  end

  # --- Screen Control Sequences ---

  # Returns escape sequence to enter alternate screen (smcup).
  def enter_ca_seq : String
    get_cap("smcup")
  end

  # Returns escape sequence to exit alternate screen (rmcup).
  def exit_ca_seq : String
    get_cap("rmcup")
  end

  # Returns escape sequence to clear screen (clear).
  def clear_screen_seq : String
    get_cap("clear")
  end

  # --- Cursor Control Sequences ---

  # Returns escape sequence to show cursor (cnorm).
  def show_cursor_seq : String
    get_cap("cnorm")
  end

  # Returns escape sequence to hide cursor (civis).
  def hide_cursor_seq : String
    get_cap("civis")
  end

  # Returns the raw cup capability string (parametrized).
  #
  # Use `cursor_position_seq` to get a ready-to-use sequence with coordinates.
  # Uses cached value to avoid hash lookup overhead.
  def cup_seq : String
    @cached_cup || get_cap("cup")
  end

  # Returns escape sequence to move cursor to position (row, col).
  #
  # Uses the terminfo `cup` capability with tparm processing.
  # Coordinates are 0-based and will be converted to 1-based by the %i
  # operation in the capability string.
  def cursor_position_seq(row : Int32, col : Int32) : String
    cap = @cached_cup || get_cap("cup")
    return "" if cap.empty?
    Tparm.process(cap, row.to_i64, col.to_i64)
  end

  # Returns the raw setaf capability string (parametrized foreground color).
  # Uses cached value to avoid hash lookup overhead.
  def setaf_seq : String
    @cached_setaf || get_cap("setaf")
  end

  # Returns the raw setab capability string (parametrized background color).
  # Uses cached value to avoid hash lookup overhead.
  def setab_seq : String
    @cached_setab || get_cap("setab")
  end

  # Returns escape sequence to set foreground color.
  #
  # Uses the terminfo `setaf` capability with tparm processing.
  def foreground_color_seq(color_index : Int32) : String
    cap = @cached_setaf || get_cap("setaf")
    return "" if cap.empty?
    Tparm.process(cap, color_index.to_i64)
  end

  # Returns escape sequence to set background color.
  #
  # Uses the terminfo `setab` capability with tparm processing.
  def background_color_seq(color_index : Int32) : String
    cap = @cached_setab || get_cap("setab")
    return "" if cap.empty?
    Tparm.process(cap, color_index.to_i64)
  end

  # --- Cursor Movement Sequences (Parametrized) ---

  # Returns escape sequence to move cursor forward N columns.
  def cursor_forward_seq(n : Int32) : String
    process_param_cap(@cached_cuf, "cuf", n)
  end

  # Returns escape sequence to move cursor backward N columns.
  def cursor_backward_seq(n : Int32) : String
    process_param_cap(@cached_cub, "cub", n)
  end

  # Returns escape sequence to move cursor up N rows.
  def cursor_up_seq(n : Int32) : String
    process_param_cap(@cached_cuu, "cuu", n)
  end

  # Returns escape sequence to move cursor down N rows.
  def cursor_down_seq(n : Int32) : String
    process_param_cap(@cached_cud, "cud", n)
  end

  # Returns escape sequence to move cursor to column N (0-based).
  def column_address_seq(col : Int32) : String
    process_param_cap(@cached_hpa, "hpa", col)
  end

  # Returns escape sequence to move cursor to row N (0-based).
  def row_address_seq(row : Int32) : String
    process_param_cap(@cached_vpa, "vpa", row)
  end

  # --- Line Editing Sequences (Parametrized) ---

  # Returns escape sequence to erase N characters at cursor.
  def erase_chars_seq(n : Int32) : String
    process_param_cap(@cached_ech, "ech", n)
  end

  # Returns escape sequence to insert N blank lines at cursor.
  def insert_lines_seq(n : Int32) : String
    process_param_cap(@cached_il, "il", n)
  end

  # Returns escape sequence to delete N lines at cursor.
  def delete_lines_seq(n : Int32) : String
    process_param_cap(@cached_dl, "dl", n)
  end

  # Processes a single-parameter capability with tparm.
  private def process_param_cap(cached : String?, name : String, param : Int32) : String
    cap = cached || get_cap(name)
    return "" if cap.empty?
    Tparm.process(cap, param.to_i64)
  end

  # --- Text Attribute Sequences ---

  # Returns escape sequence to reset all attributes (sgr0).
  def reset_attrs_seq : String
    get_cap("sgr0")
  end

  # Returns escape sequence to enable underline (smul).
  def underline_seq : String
    get_cap("smul")
  end

  # Returns escape sequence to enable bold (bold).
  def bold_seq : String
    get_cap("bold")
  end

  # Returns escape sequence to enable blink (blink).
  def blink_seq : String
    get_cap("blink")
  end

  # Returns escape sequence to enable reverse video (rev).
  def reverse_seq : String
    get_cap("rev")
  end

  # Returns escape sequence to enable dim/faint mode (dim).
  def dim_seq : String
    get_cap("dim")
  end

  # Returns escape sequence to enable italic/cursive mode (sitm).
  def italic_seq : String
    get_cap("sitm")
  end

  # Returns escape sequence to enable hidden/invisible mode (invis).
  def hidden_seq : String
    get_cap("invis")
  end

  # Returns escape sequence to enable strikethrough mode (smxx).
  def strikethrough_seq : String
    get_cap("smxx")
  end

  # --- Keypad Control Sequences ---

  # Returns escape sequence to enter keypad mode (smkx).
  def enter_keypad_seq : String
    get_cap("smkx")
  end

  # Returns escape sequence to exit keypad mode (rmkx).
  def exit_keypad_seq : String
    get_cap("rmkx")
  end
end

require "./terminfo/*"
