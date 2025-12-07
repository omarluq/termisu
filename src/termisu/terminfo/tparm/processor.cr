# Internal processor for terminfo parametrized string processing.
#
# Implements a stack-based interpreter for the terminfo parametrized string
# format as defined in terminfo(5). This is the core engine that transforms
# capability templates like `\e[%i%p1%d;%p2%dH` into actual escape sequences.
#
# ## Stack Machine Architecture
#
# The processor maintains:
# - A value stack for intermediate computations
# - Dynamic variables (a-z) scoped to this processing call
# - Static variables (A-Z) shared across all tparm calls in a session
# - An output buffer for the result string
# - A position cursor for parsing the format string
#
# ## Processing Flow
#
# 1. Scan format string byte-by-byte
# 2. Literal characters go directly to output
# 3. `%` triggers escape sequence processing
# 4. Escape codes manipulate the stack or produce output
# 5. Final output buffer contents are returned
require "./operations"
require "./output"
require "./variables"
require "./conditional"

class Termisu::Terminfo::Tparm::Processor
  include Output
  include Variables
  include Conditional

  INITIAL_STACK_CAPACITY  =  8
  INITIAL_OUTPUT_CAPACITY = 32

  @format : String
  @params : Array(Int64)
  @stack : Array(Int64)
  @output : IO::Memory
  @pos : Int32
  @format_size : Int32
  @dynamic_vars : Hash(Char, Int64)
  @static_vars : Hash(Char, Int64)

  @@static_storage : Hash(Char, Int64) = {} of Char => Int64

  def initialize(@format : String, @params : Array(Int64))
    @stack = Array(Int64).new(INITIAL_STACK_CAPACITY)
    @output = IO::Memory.new(INITIAL_OUTPUT_CAPACITY)
    @pos = 0
    @format_size = @format.bytesize
    @dynamic_vars = {} of Char => Int64
    @static_vars = @@static_storage
  end

  # Executes the tparm processor and returns the formatted string.
  def run : String
    while @pos < @format_size
      byte = @format.byte_at(@pos)
      if byte == '%'.ord
        process_escape
      else
        @output.write_byte(byte)
      end
      @pos += 1
    end
    @output.to_s
  end

  # Processes a single escape sequence starting after the % character.
  private def process_escape
    @pos += 1
    return if @pos >= @format_size

    char = @format.byte_at(@pos).unsafe_chr

    if op = Operations::BINARY[char]?
      apply_binary_op(op)
      return
    end

    dispatch_non_binary_op(char)
  end

  @[AlwaysInline]
  private def apply_binary_op(op : Proc(Int64, Int64, Int64))
    right = pop
    left = pop
    push(op.call(left, right))
  end

  private def dispatch_non_binary_op(char : Char)
    dispatch_output_op(char) ||
      dispatch_variable_op(char) ||
      dispatch_constant_op(char) ||
      dispatch_special_op(char)
  end

  @[AlwaysInline]
  private def dispatch_output_op(char : Char) : Bool
    case char
    when '%' then @output.write_byte('%'.ord.to_u8)
    when 'd' then output_decimal
    when 'c' then output_char
    when 's' then output_string
    else          return false
    end
    true
  end

  @[AlwaysInline]
  private def dispatch_variable_op(char : Char) : Bool
    case char
    when 'p' then push_param
    when 'P' then set_variable
    when 'g' then get_variable
    else          return false
    end
    true
  end

  @[AlwaysInline]
  private def dispatch_constant_op(char : Char) : Bool
    case char
    when '\'' then push_char_const
    when '{'  then push_int_const
    else           return false
    end
    true
  end

  @[AlwaysInline]
  private def dispatch_special_op(char : Char) : Bool
    case char
    when 'i' then increment_params
    when 'l' then push_length
    when '!' then push_logical_not
    when '~' then push_bitwise_not
    when '?' then process_conditional
    else          return false
    end
    true
  end

  # --- Stack Operations ---

  @[AlwaysInline]
  private def push(val : Int64)
    @stack << val
  end

  @[AlwaysInline]
  private def pop : Int64
    @stack.pop? || 0_i64
  end

  # Clears all static variables.
  def self.clear_static_vars
    @@static_storage.clear
  end
end
