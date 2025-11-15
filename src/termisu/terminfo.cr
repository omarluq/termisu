class Termisu::Terminfo
  @funcs : Array(String)
  @keys : Array(String)

  def initialize
    name = ENV["TERM"]? || raise Termisu::Error.new("TERM environment variable not set")

    @funcs = load_capabilities(name, Capabilities::FUNCS_INDICES) do
      Builtin.funcs_for(name)
    end

    @keys = load_capabilities(name, Capabilities::KEYS_INDICES) do
      Builtin.keys_for(name)
    end
  end

  private def load_capabilities(name : String, indices : Array(Int16), & : -> Array(String)) : Array(String)
    data = Database.new(name).load
    Parser.parse(data, indices)
  rescue ex : Exception
    # Fall back to builtin capabilities if database load or parse fails
    yield
  end

  # Convenience accessors with bounds checking
  def enter_ca : String
    @funcs.fetch(0, "")
  end

  def exit_ca : String
    @funcs.fetch(1, "")
  end

  def show_cursor : String
    @funcs.fetch(2, "")
  end

  def hide_cursor : String
    @funcs.fetch(3, "")
  end

  def clear_screen : String
    @funcs.fetch(4, "")
  end

  def sgr0 : String
    @funcs.fetch(5, "")
  end

  def underline : String
    @funcs.fetch(6, "")
  end

  def bold : String
    @funcs.fetch(7, "")
  end

  def blink : String
    @funcs.fetch(8, "")
  end

  def reverse : String
    @funcs.fetch(9, "")
  end

  def enter_keypad : String
    @funcs.fetch(10, "")
  end

  def exit_keypad : String
    @funcs.fetch(11, "")
  end
end

require "./terminfo/*"
