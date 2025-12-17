# Terminfo database file locator and loader.
#
# Searches for compiled terminfo database files in standard locations
# following the terminfo directory hierarchy conventions used by ncurses.
#
# ## Search Order
#
# 1. `$TERMINFO` environment variable
# 2. `$HOME/.terminfo` (user-specific database)
# 3. `$TERMINFO_DIRS` (colon-separated list)
# 4. `/lib/terminfo` (system library)
# 5. `/usr/local/share/terminfo` (FreeBSD ports, Homebrew)
# 6. `/usr/share/terminfo` (standard location)
#
# ## Path Formats
#
# Supports both standard Unix and Darwin/macOS path formats:
# - Unix: `/usr/share/terminfo/x/xterm-256color`
# - Darwin: `/usr/share/terminfo/78/xterm-256color` (hex first char)
#
# ## Example
#
# ```
# db = Termisu::Terminfo::Database.new("xterm-256color")
# data = db.load # => Bytes containing compiled terminfo
# ```
class Termisu::Terminfo::Database
  Log = Termisu::Logs::Terminfo
  @name : String

  # Creates a new Database instance for the given terminal name.
  #
  # Parameters:
  # - name: Terminal name (e.g., "xterm-256color", "linux")
  def initialize(@name : String)
  end

  # Loads the terminfo database for this terminal.
  #
  # Searches standard locations in order until a matching database is found.
  #
  # Returns the raw binary data as Bytes.
  #
  # Raises an exception if no database is found in any location.
  def load : Bytes
    Log.trace { "Searching for terminfo database: #{@name}" }
    try_terminfo_env ||
      try_home_terminfo ||
      try_terminfo_dirs ||
      try_lib_terminfo ||
      try_usr_local_share ||
      try_usr_share ||
      raise "Could not find terminfo database for #{@name}"
  end

  private def try_terminfo_env : Bytes?
    if terminfo = ENV["TERMINFO"]?
      try_path(terminfo)
    end
  end

  private def try_home_terminfo : Bytes?
    if home = ENV["HOME"]?
      try_path("#{home}/.terminfo")
    end
  end

  private def try_terminfo_dirs : Bytes?
    if dirs = ENV["TERMINFO_DIRS"]?
      dirs.split(":").each do |dir|
        dir = "/usr/share/terminfo" if dir.empty?
        if data = try_path(dir)
          return data
        end
      end
    end
    nil
  end

  private def try_lib_terminfo : Bytes?
    try_path("/lib/terminfo")
  end

  private def try_usr_local_share : Bytes?
    try_path("/usr/local/share/terminfo")
  end

  private def try_usr_share : Bytes?
    try_path("/usr/share/terminfo")
  end

  private def try_path(base : String) : Bytes?
    # Standard *nix path: /usr/share/terminfo/x/xterm-256color
    path = File.join(base, @name[0].to_s, @name)
    if File.exists?(path)
      Log.debug { "Found terminfo at #{path}" }
      return File.read(path).to_slice
    end

    # Darwin format: /usr/share/terminfo/78/xterm-256color
    hex = @name[0].ord.to_s(16)
    path = File.join(base, hex, @name)
    if File.exists?(path)
      Log.debug { "Found terminfo at #{path} (Darwin format)" }
      return File.read(path).to_slice
    end

    Log.trace { "Terminfo not found at #{base}" }
    nil
  rescue ex
    Log.trace { "Error reading #{base}: #{ex.message}" }
    nil
  end
end
