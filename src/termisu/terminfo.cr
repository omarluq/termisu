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

  # The standard ANSI cup capability, byte-identical to the xterm/linux
  # builtins. When the loaded cup matches this exactly, `cursor_position_seq`
  # takes a direct-interpolation fast path instead of the tparm interpreter.
  private STANDARD_CUP = "\e[%i%p1%d;%p2%dH"

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

  # Cached capability strings for frequently-emitted attribute and cursor
  # sequences. These avoid a hash lookup per escape-sequence emission during
  # rendering (RenderState re-emits them on every style change).
  @cached_sgr0 : String?
  @cached_bold : String?
  @cached_smul : String?
  @cached_blink : String?
  @cached_rev : String?
  @cached_dim : String?
  @cached_sitm : String?
  @cached_invis : String?
  @cached_smxx : String?
  @cached_cnorm : String?
  @cached_civis : String?
  @cached_cvvis : String?

  # True when the loaded cup capability equals STANDARD_CUP. Set once during
  # initialization and never mutated afterwards (fiber-safe). Exposed so
  # Terminal can stream CSI cursor moves directly (byte-identical to
  # `cursor_position_seq` output) without a per-move String.
  getter? cup_is_standard = false

  # True when every attribute-enable capability equals its standard ECMA-48
  # SGR sequence (byte-identical to the xterm/linux builtins). Set once during
  # initialization and never mutated afterwards (fiber-safe). Exposed so
  # Terminal's combined apply_sgr path only emits hardcoded SGR parameters
  # when they match what the granular terminfo-driven path would produce;
  # exotic TERMs with non-CSI attribute sequences fall back to that path.
  getter? attrs_are_standard = false

  # Cross-init cache of merged capability hashes keyed by TERM: locating,
  # reading, and parsing a terminfo file is invariant per TERM within a
  # process, so repeated `Terminfo.new` shares one hash. A cached hash is
  # immutable after being stored — instances only read it via `get_cap` —
  # which makes sharing safe across fibers and threads.
  #
  # The lock is a raw atomic spinlock rather than `Mutex` (same rationale as
  # `FFI::ErrorState`): `Terminfo.new` runs on the FFI create path, which may
  # be entered from arbitrary host threads where parking a fiber through the
  # scheduler aborts the process. Critical sections are a single Hash op.
  @@cache_lock = Atomic(Bool).new(false)
  @@caps_cache = {} of String => Hash(String, String)

  def initialize
    term_name = ENV["TERM"]? || raise Termisu::Error.new("TERM environment variable not set")
    Log.info { "Loading terminfo for TERM=#{term_name}" }

    @caps = self.class.caps_for(term_name)
    cache_frequent_capabilities
    Log.debug { "Loaded #{@caps.size} capabilities" }
  end

  # Returns the merged capability hash for *term_name*, building and caching
  # it on first use. The returned hash is shared and must not be mutated.
  protected def self.caps_for(term_name : String) : Hash(String, String)
    if cached = cache_sync { @@caps_cache[term_name]? }
      return cached
    end

    # Built outside the lock: loading does file I/O. Concurrent builders may
    # race, but every result is equivalent and immutable, so last-write wins.
    caps = build_caps(term_name)
    cache_sync { @@caps_cache[term_name] = caps }
    caps
  end

  # :nodoc:
  # Test hook: returns the cached hash for *term_name*, if present.
  def self.cached_caps?(term_name : String) : Hash(String, String)?
    cache_sync { @@caps_cache[term_name]? }
  end

  # :nodoc:
  # Test hook: drops all cached capability hashes.
  def self.clear_caps_cache : Nil
    cache_sync { @@caps_cache.clear }
  end

  # Builds the merged (database + builtin fallback) capability hash.
  private def self.build_caps(term_name : String) : Hash(String, String)
    caps = load_from_database(term_name)
    fill_missing_with_builtins(caps, term_name)
    caps
  end

  private def self.cache_sync(&)
    until @@cache_lock.compare_and_set(false, true, :acquire, :relaxed)[1]
    end
    begin
      yield
    ensure
      @@cache_lock.set(false, :release)
    end
  end

  # Pre-caches frequently-used parametrized capability strings.
  private def cache_frequent_capabilities
    @cached_cup = get_cap("cup")
    @cup_is_standard = @cached_cup == STANDARD_CUP
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
    @cached_sgr0 = get_cap("sgr0")
    @cached_bold = get_cap("bold")
    @cached_smul = get_cap("smul")
    @cached_blink = get_cap("blink")
    @cached_rev = get_cap("rev")
    @cached_dim = get_cap("dim")
    @cached_sitm = get_cap("sitm")
    @cached_invis = get_cap("invis")
    @cached_smxx = get_cap("smxx")
    @cached_cnorm = get_cap("cnorm")
    @cached_civis = get_cap("civis")
    @cached_cvvis = get_cap("cvvis")
    @attrs_are_standard = @cached_bold == "\e[1m" && @cached_dim == "\e[2m" &&
                          @cached_sitm == "\e[3m" && @cached_smul == "\e[4m" &&
                          @cached_blink == "\e[5m" && @cached_rev == "\e[7m" &&
                          @cached_invis == "\e[8m" && @cached_smxx == "\e[9m"
  end

  # Loads capabilities from the terminfo database.
  private def self.load_from_database(term_name : String) : Hash(String, String)
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
  private def self.fill_missing_with_builtins(caps : Hash(String, String), term_name : String)
    before_count = caps.size
    fill_capability_group(caps, Capabilities::REQUIRED_FUNCS, Builtin.funcs_for(term_name))
    fill_capability_group(caps, Capabilities::REQUIRED_KEYS, Builtin.keys_for(term_name))
    added = caps.size - before_count
    Log.debug { "Filled #{added} missing capabilities from builtins" } if added > 0
  end

  # Fills missing capabilities from a builtin array.
  private def self.fill_capability_group(caps : Hash(String, String), names : Array(String), values : Array(String))
    names.each_with_index do |cap_name, idx|
      caps[cap_name] ||= values[idx]
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

  # Returns escape sequence to status line (tsl).
  def to_status_line_seq : String
    "\033]0;" # tsl and fsl apparently tend to be missing, so we're hardcoding them
  end

  # Returns escape sequence for from status line (fsl).
  def from_status_line_seq : String
    "\007"
  end

  # --- Cursor Control Sequences ---

  # Returns escape sequence to show cursor (cnorm).
  # Uses cached value to avoid hash lookup overhead.
  def show_cursor_seq : String
    @cached_cnorm || get_cap("cnorm")
  end

  # Returns escape sequence to hide cursor (civis).
  # Uses cached value to avoid hash lookup overhead.
  def hide_cursor_seq : String
    @cached_civis || get_cap("civis")
  end

  # Returns escape sequence to make cursor blink/very visible (cvvis).
  # Uses cached value to avoid hash lookup overhead.
  def blink_cursor_seq : String
    @cached_cvvis || get_cap("cvvis")
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
  # Coordinates are 0-based and converted to 1-based by the %i operation in
  # the capability string. When the loaded `cup` is the standard ANSI
  # template, a direct-interpolation fast path is used (byte-identical to
  # tparm output); non-standard cup strings fall back to tparm processing.
  def cursor_position_seq(row : Int32, col : Int32) : String
    # Int64 arithmetic matches tparm's %i semantics exactly (Int32 `+ 1`
    # would overflow at Int32::MAX where tparm emits "2147483648").
    return "\e[#{row.to_i64 + 1};#{col.to_i64 + 1}H" if @cup_is_standard

    process_param_cap(@cached_cup, "cup", row, col)
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
    process_param_cap(@cached_setaf, "setaf", color_index)
  end

  # Returns escape sequence to set background color.
  #
  # Uses the terminfo `setab` capability with tparm processing.
  def background_color_seq(color_index : Int32) : String
    process_param_cap(@cached_setab, "setab", color_index)
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

  # Processes a two-parameter capability with tparm.
  private def process_param_cap(cached : String?, name : String, first : Int32, second : Int32) : String
    cap = cached || get_cap(name)
    return "" if cap.empty?
    Tparm.process(cap, first.to_i64, second.to_i64)
  end

  # --- Text Attribute Sequences ---

  # Returns escape sequence to reset all attributes (sgr0).
  # Uses cached value to avoid hash lookup overhead.
  def reset_attrs_seq : String
    @cached_sgr0 || get_cap("sgr0")
  end

  # Returns escape sequence to enable underline (smul).
  # Uses cached value to avoid hash lookup overhead.
  def underline_seq : String
    @cached_smul || get_cap("smul")
  end

  # Returns escape sequence to enable bold (bold).
  # Uses cached value to avoid hash lookup overhead.
  def bold_seq : String
    @cached_bold || get_cap("bold")
  end

  # Returns escape sequence to enable blink (blink).
  # Uses cached value to avoid hash lookup overhead.
  def blink_seq : String
    @cached_blink || get_cap("blink")
  end

  # Returns escape sequence to enable reverse video (rev).
  # Uses cached value to avoid hash lookup overhead.
  def reverse_seq : String
    @cached_rev || get_cap("rev")
  end

  # Returns escape sequence to enable dim/faint mode (dim).
  # Uses cached value to avoid hash lookup overhead.
  def dim_seq : String
    @cached_dim || get_cap("dim")
  end

  # Returns escape sequence to enable italic/cursive mode (sitm).
  # Uses cached value to avoid hash lookup overhead.
  def italic_seq : String
    @cached_sitm || get_cap("sitm")
  end

  # Returns escape sequence to enable hidden/invisible mode (invis).
  # Uses cached value to avoid hash lookup overhead.
  def hidden_seq : String
    @cached_invis || get_cap("invis")
  end

  # Returns escape sequence to enable strikethrough mode (smxx).
  # Uses cached value to avoid hash lookup overhead.
  def strikethrough_seq : String
    @cached_smxx || get_cap("smxx")
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
