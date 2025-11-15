class Termisu::Terminfo::Database
  @name : String

  def initialize(@name : String)
  end

  def load : Bytes
    try_terminfo_env ||
      try_home_terminfo ||
      try_terminfo_dirs ||
      try_lib_terminfo ||
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

  private def try_usr_share : Bytes?
    try_path("/usr/share/terminfo")
  end

  private def try_path(base : String) : Bytes?
    # Standard *nix path: /usr/share/terminfo/x/xterm-256color
    path = File.join(base, @name[0].to_s, @name)
    return File.read(path).to_slice if File.exists?(path)

    # Darwin format: /usr/share/terminfo/78/xterm-256color
    hex = @name[0].ord.to_s(16)
    path = File.join(base, hex, @name)
    File.read(path).to_slice if File.exists?(path)
  rescue
    nil
  end
end
