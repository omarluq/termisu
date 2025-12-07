# Terminfo parametrized string processor (tparm).
#
# Implements the terminfo string parameter processing algorithm as defined in
# terminfo(5). This is a stack-based interpreter that processes capability
# strings containing special % codes to produce terminal control sequences.
#
# ## Supported Operations
#
# **Parameters:**
# - `%p[1-9]` - Push parameter onto stack (1-indexed)
# - `%P[a-z]` - Set dynamic variable
# - `%g[a-z]` - Get dynamic variable
# - `%P[A-Z]` - Set static variable
# - `%g[A-Z]` - Get static variable
#
# **Output:**
# - `%d` - Pop and output as decimal
# - `%s` - Pop and output as string
# - `%c` - Pop and output as character (ASCII code)
# - `%%` - Output literal %
#
# **Constants:**
# - `%{nn}` - Push integer constant
# - `%'c'` - Push ASCII value of character
#
# **Arithmetic:** `%+`, `%-`, `%*`, `%/`, `%m` (modulo)
#
# **Bitwise:** `%&`, `%|`, `%^` (AND, OR, XOR)
#
# **Comparison:** `%=`, `%<`, `%>`
#
# **Logical:** `%A` (AND), `%O` (OR), `%!`, `%~`
#
# **Special:**
# - `%i` - Increment first two parameters (ANSI terminals)
# - `%l` - Push string length
#
# **Conditionals:**
# - `%? expr %t then %e else %;` - If-then-else
#
# ## Example
#
# ```
# # cup capability: \e[%i%p1%d;%p2%dH
# # With parameters row=5, col=10:
# result = Termisu::Terminfo::Tparm.process("\e[%i%p1%d;%p2%dH", 5, 10)
# # => "\e[6;11H" (incremented due to %i)
# ```
require "./tparm/processor"

module Termisu::Terminfo::Tparm
  # Processes a parametrized terminfo capability string with no parameters.
  def self.process(format : String) : String
    process(format, [] of Int64)
  end

  # Processes a parametrized terminfo capability string with the given parameters.
  def self.process(format : String, *params : Int) : String
    arr = Array(Int64).new(params.size)
    params.each { |param| arr << param.to_i64 }
    process(format, arr)
  end

  # Processes a parametrized terminfo capability string with an array of parameters.
  def self.process(format : String, params : Array(Int64)) : String
    Processor.new(format, params).run
  end
end
