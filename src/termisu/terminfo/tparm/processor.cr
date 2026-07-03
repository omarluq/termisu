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
  @output : String::Builder
  @pos : Int32
  @format_size : Int32
  @dynamic_vars : Hash(Char, Int64)?
  @static_vars : Hash(Char, Int64)

  @@static_storage : Hash(Char, Int64) = {} of Char => Int64

  def initialize(@format : String, @params : Array(Int64))
    @stack = Array(Int64).new(INITIAL_STACK_CAPACITY)
    @output = String::Builder.new(INITIAL_OUTPUT_CAPACITY)
    @pos = 0
    @format_size = @format.bytesize
    @dynamic_vars = nil
    @static_vars = @@static_storage
  end

  # Executes the tparm processor and returns the formatted string.
  #
  # Must be called at most once per Processor instance: the output buffer is
  # a String::Builder, whose `to_s` is single-shot. Processor is single-use
  # by design (sole call site: `Tparm.process`).
  def run : String
    slice = @format.to_slice
    percent = '%'.ord.to_u8
    while @pos < @format_size
      if slice.unsafe_fetch(@pos) == percent
        process_escape
        @pos += 1
      else
        # Batch the literal run into a single slice write. unsafe_fetch is
        # in-bounds: @pos < @format_size == slice.size (as in variables.cr).
        start = @pos
        while @pos < @format_size && slice.unsafe_fetch(@pos) != percent
          @pos += 1
        end
        @output.write(slice[start, @pos - start])
      end
    end
    @output.to_s
  end

  # Processes a single escape sequence starting after the % character.
  private def process_escape
    @pos += 1
    return if @pos >= @format_size

    char = @format.byte_at(@pos).unsafe_chr

    return if dispatch_binary_op(char)

    dispatch_non_binary_op(char)
  end

  # Pops two operands (right first, then left), applies the block, and pushes
  # the result. Yield-based so operator bodies inline into the dispatchers.
  private def binary_op(& : Int64, Int64 -> Int64)
    right = pop
    left = pop
    push(yield(left, right))
  end

  @[AlwaysInline]
  private def to_flag(value : Bool) : Int64
    value ? 1_i64 : 0_i64
  end

  private def dispatch_binary_op(char : Char) : Bool
    dispatch_arithmetic_op(char) ||
      dispatch_bitwise_op(char) ||
      dispatch_compare_op(char)
  end

  @[AlwaysInline]
  private def dispatch_arithmetic_op(char : Char) : Bool
    case char
    when '+' then binary_op { |left, right| left + right }
    when '-' then binary_op { |left, right| left - right }
    when '*' then binary_op { |left, right| left * right }
    when '/' then binary_op { |left, right| right != 0 ? left // right : 0_i64 }
    when 'm' then binary_op { |left, right| right != 0 ? left % right : 0_i64 }
    else          return false
    end
    true
  end

  @[AlwaysInline]
  private def dispatch_bitwise_op(char : Char) : Bool
    case char
    when '&' then binary_op { |left, right| left & right }
    when '|' then binary_op { |left, right| left | right }
    when '^' then binary_op { |left, right| left ^ right }
    else          return false
    end
    true
  end

  @[AlwaysInline]
  private def dispatch_compare_op(char : Char) : Bool
    case char
    when '=' then binary_op { |left, right| to_flag(left == right) }
    when '<' then binary_op { |left, right| to_flag(left < right) }
    when '>' then binary_op { |left, right| to_flag(left > right) }
    when 'A' then binary_op { |left, right| to_flag(left != 0 && right != 0) }
    when 'O' then binary_op { |left, right| to_flag(left != 0 || right != 0) }
    else          return false
    end
    true
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

  # Lazily allocated: %P/%g never appear in hot render-path capabilities
  # (cup, cuf, setaf...), so most calls never need this hash.
  private def dynamic_vars : Hash(Char, Int64)
    @dynamic_vars ||= {} of Char => Int64
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
