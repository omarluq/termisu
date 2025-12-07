# Internal processor for terminfo parametrized string processing.
require "./operations"

class Termisu::Terminfo::Tparm::Processor
  @format : String
  @params : Array(Int64)
  @stack : Array(Int64)
  @output : IO::Memory
  @pos : Int32
  @dynamic_vars : Hash(Char, Int64)
  @static_vars : Hash(Char, Int64)

  # Static variables are shared across all tparm calls in a session.
  @@static_storage : Hash(Char, Int64) = {} of Char => Int64

  def initialize(@format : String, @params : Array(Int64))
    @stack = [] of Int64
    @output = IO::Memory.new
    @pos = 0
    @dynamic_vars = {} of Char => Int64
    @static_vars = @@static_storage
  end

  def run : String
    format_size = @format.bytesize
    while @pos < format_size
      char = @format.byte_at(@pos).unsafe_chr
      if char == '%'
        process_escape
      else
        @output << char
      end
      @pos += 1
    end
    @output.to_s
  end

  private def process_escape
    @pos += 1
    return if @pos >= @format.bytesize

    char = @format.byte_at(@pos).unsafe_chr

    # Fast path: check binary ops hash first
    if op = Operations::BINARY[char]?
      apply_binary_op(op)
      return
    end

    process_other_escape(char)
  end

  private def apply_binary_op(op)
    right = pop
    left = pop
    push(op.call(left, right))
  end

  private def process_other_escape(char : Char)
    return process_output_op(char) if process_output_op?(char)
    return process_variable_op(char) if process_variable_op?(char)
    return process_constant_op(char) if process_constant_op?(char)
    process_special_op(char)
  end

  @[AlwaysInline]
  private def process_output_op?(char : Char) : Bool
    Operations::OUTPUT_OPS.includes?(char)
  end

  private def process_output_op(char : Char)
    case char
    when '%' then @output << '%'
    when 'c' then output_char
    when 'd' then output_decimal
    when 's' then output_string
    end
  end

  @[AlwaysInline]
  private def process_variable_op?(char : Char) : Bool
    Operations::VARIABLE_OPS.includes?(char)
  end

  private def process_variable_op(char : Char)
    case char
    when 'p' then push_param
    when 'P' then set_variable
    when 'g' then get_variable
    end
  end

  @[AlwaysInline]
  private def process_constant_op?(char : Char) : Bool
    Operations::CONSTANT_OPS.includes?(char)
  end

  private def process_constant_op(char : Char)
    case char
    when '\'' then push_char_const
    when '{'  then push_int_const
    end
  end

  private def process_special_op(char : Char)
    case char
    when 'i' then increment_params
    when 'l' then push_length
    when '!' then push_logical_not
    when '~' then push_bitwise_not
    when '?' then process_conditional
    end
  end

  @[AlwaysInline]
  private def output_char
    @output << pop.to_i.unsafe_chr
  end

  @[AlwaysInline]
  private def output_decimal
    @output << pop.to_s
  end

  @[AlwaysInline]
  private def output_string
    @output << pop.to_s
  end

  @[AlwaysInline]
  private def push_length
    push(pop.to_s.size.to_i64)
  end

  @[AlwaysInline]
  private def push_logical_not
    push(pop == 0 ? 1_i64 : 0_i64)
  end

  @[AlwaysInline]
  private def push_bitwise_not
    push(~pop)
  end

  private def push_param
    @pos += 1
    return if @pos >= @format.bytesize
    param_idx = @format.byte_at(@pos).unsafe_chr.ord - '1'.ord
    if param_idx >= 0 && param_idx < 9
      push(param_idx < @params.size ? @params.unsafe_fetch(param_idx) : 0_i64)
    end
  end

  private def set_variable
    @pos += 1
    return if @pos >= @format.bytesize
    var = @format.byte_at(@pos).unsafe_chr
    val = pop
    if var >= 'a' && var <= 'z'
      @dynamic_vars[var] = val
    elsif var >= 'A' && var <= 'Z'
      @static_vars[var] = val
    end
  end

  private def get_variable
    @pos += 1
    return if @pos >= @format.bytesize
    var = @format.byte_at(@pos).unsafe_chr
    if var >= 'a' && var <= 'z'
      push(@dynamic_vars.fetch(var, 0_i64))
    elsif var >= 'A' && var <= 'Z'
      push(@static_vars.fetch(var, 0_i64))
    end
  end

  private def push_char_const
    @pos += 1
    return if @pos >= @format.bytesize
    push(@format.byte_at(@pos).to_i64)
    @pos += 1 # Skip closing quote
  end

  private def push_int_const
    @pos += 1
    start_pos = @pos
    while @pos < @format.bytesize && @format.byte_at(@pos).unsafe_chr != '}'
      @pos += 1
    end
    num_str = @format[start_pos...@pos]
    push(num_str.to_i64? || 0_i64)
  end

  private def increment_params
    @params[0] = @params[0] + 1 if @params.size > 0
    @params[1] = @params[1] + 1 if @params.size > 1
  end

  private def process_conditional
    skip_to_then
    condition = pop != 0

    if condition
      process_then_part
      skip_else_part
    else
      skip_then_part
      process_else_part
    end
  end

  private def process_escape_for_condition
    @pos += 1
    return if @pos >= @format.bytesize

    char = @format.byte_at(@pos).unsafe_chr

    # Fast path: binary ops
    if op = Operations::BINARY[char]?
      apply_binary_op(op)
      return
    end

    case char
    when 'p'  then push_param
    when '\'' then push_char_const
    when '{'  then push_int_const
    when '!'  then push(pop == 0 ? 1_i64 : 0_i64)
    when '~'  then push(~pop)
    when 'g'  then get_variable
    end
  end

  private def skip_to_then
    format_size = @format.bytesize
    while @pos < format_size
      if @format.byte_at(@pos).unsafe_chr == '%'
        @pos += 1
        return if @pos >= format_size
        char = @format.byte_at(@pos).unsafe_chr
        if char == 't'
          return
        else
          @pos -= 1
          process_escape_for_condition
        end
      end
      @pos += 1
    end
  end

  private def process_then_part
    nesting = 1
    format_size = @format.bytesize
    while @pos < format_size
      @pos += 1
      return if @pos >= format_size

      char = @format.byte_at(@pos).unsafe_chr
      if char == '%'
        @pos += 1
        return if @pos >= format_size
        ctrl = @format.byte_at(@pos).unsafe_chr
        case ctrl
        when '?' then nesting += 1
        when ';'
          nesting -= 1
          return if nesting == 0
        when 'e'
          return if nesting == 1
        else
          @pos -= 1
          process_escape
        end
      else
        @output << char
      end
    end
  end

  private def skip_then_part
    nesting = 1
    format_size = @format.bytesize
    while @pos < format_size
      @pos += 1
      return if @pos >= format_size

      if @format.byte_at(@pos).unsafe_chr == '%'
        @pos += 1
        return if @pos >= format_size
        ctrl = @format.byte_at(@pos).unsafe_chr
        case ctrl
        when '?' then nesting += 1
        when ';'
          nesting -= 1
          return if nesting == 0
        when 'e'
          return if nesting == 1
        end
      end
    end
  end

  private def process_else_part
    nesting = 1
    format_size = @format.bytesize
    while @pos < format_size
      @pos += 1
      return if @pos >= format_size

      char = @format.byte_at(@pos).unsafe_chr
      if char == '%'
        @pos += 1
        return if @pos >= format_size
        ctrl = @format.byte_at(@pos).unsafe_chr
        case ctrl
        when '?' then nesting += 1
        when ';'
          nesting -= 1
          return if nesting == 0
        else
          @pos -= 1
          process_escape
        end
      else
        @output << char
      end
    end
  end

  private def skip_else_part
    nesting = 1
    format_size = @format.bytesize
    while @pos < format_size
      @pos += 1
      return if @pos >= format_size

      if @format.byte_at(@pos).unsafe_chr == '%'
        @pos += 1
        return if @pos >= format_size
        ctrl = @format.byte_at(@pos).unsafe_chr
        case ctrl
        when '?' then nesting += 1
        when ';'
          nesting -= 1
          return if nesting == 0
        end
      end
    end
  end

  @[AlwaysInline]
  private def push(val : Int64)
    @stack << val
  end

  @[AlwaysInline]
  private def pop : Int64
    @stack.pop? || 0_i64
  end
end
