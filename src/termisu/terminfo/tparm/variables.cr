# Variable and parameter operations for tparm processor.
#
# Handles parameter access (%p), variable storage (%P), retrieval (%g),
# constants (%{n}, %'c'), and parameter increment (%i).
module Termisu::Terminfo::Tparm::Variables
  # %p1-%p9 - Push parameter N onto stack (1-indexed in format, 0-indexed in array).
  private def push_param
    @pos += 1
    return if @pos >= @format_size
    param_idx = @format.byte_at(@pos).unsafe_chr.ord - '1'.ord
    if param_idx >= 0 && param_idx < 9
      push(param_idx < @params.size ? @params.unsafe_fetch(param_idx) : 0_i64)
    end
  end

  # %Pa-%Pz or %PA-%PZ - Pop value and store in variable.
  private def set_variable
    @pos += 1
    return if @pos >= @format_size
    var = @format.byte_at(@pos).unsafe_chr
    val = pop
    if var >= 'a' && var <= 'z'
      @dynamic_vars[var] = val
    elsif var >= 'A' && var <= 'Z'
      @static_vars[var] = val
    end
  end

  # %ga-%gz or %gA-%gZ - Push variable value onto stack.
  private def get_variable
    @pos += 1
    return if @pos >= @format_size
    var = @format.byte_at(@pos).unsafe_chr
    if var >= 'a' && var <= 'z'
      push(@dynamic_vars.fetch(var, 0_i64))
    elsif var >= 'A' && var <= 'Z'
      push(@static_vars.fetch(var, 0_i64))
    end
  end

  # %'c' - Push ASCII value of character c.
  private def push_char_const
    @pos += 1
    return if @pos >= @format_size
    push(@format.byte_at(@pos).to_i64)
    @pos += 1 # Skip closing quote
  end

  # %{nn} - Push integer constant nn.
  private def push_int_const
    @pos += 1
    start_pos = @pos
    while @pos < @format_size && @format.byte_at(@pos).unsafe_chr != '}'
      @pos += 1
    end
    num_str = @format[start_pos...@pos]
    push(num_str.to_i64? || 0_i64)
  end

  # %i - Increment first two parameters by 1.
  private def increment_params
    @params[0] = @params[0] + 1 if @params.size > 0
    @params[1] = @params[1] + 1 if @params.size > 1
  end
end
