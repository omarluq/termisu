# Conditional processing for tparm processor.
#
# Handles %? ... %t ... %e ... %; conditional constructs.
# Conditionals follow the pattern: %? <condition> %t <then-part> %e <else-part> %;
# The condition is evaluated by processing escape codes until %t is reached.
# The result on the stack determines which branch to execute.
module Termisu::Terminfo::Tparm::Conditional
  # %? - Begin conditional. Evaluate condition, then branch.
  private def process_conditional
    skip_to_then
    condition = pop != 0

    if condition
      process_branch(stop_on_else: true)
      skip_branch(stop_on_else: false)
    else
      skip_branch(stop_on_else: true)
      process_branch(stop_on_else: false)
    end
  end

  # Process escape codes that can appear in condition expressions.
  private def process_escape_for_condition
    @pos += 1
    return if @pos >= @format_size

    char = @format.byte_at(@pos).unsafe_chr

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

  # Scan forward processing condition until %t is found.
  private def skip_to_then
    while @pos < @format_size
      if @format.byte_at(@pos).unsafe_chr == '%'
        @pos += 1
        return if @pos >= @format_size
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

  # Process a conditional branch with output.
  private def process_branch(stop_on_else : Bool)
    nesting = 1
    while @pos < @format_size
      @pos += 1
      return if @pos >= @format_size

      char = @format.byte_at(@pos).unsafe_chr
      if char == '%'
        action, nesting = handle_branch_control(nesting, stop_on_else, process: true)
        return if action == :stop
      else
        @output << char
      end
    end
  end

  # Skip a conditional branch without output.
  private def skip_branch(stop_on_else : Bool)
    nesting = 1
    while @pos < @format_size
      @pos += 1
      return if @pos >= @format_size

      if @format.byte_at(@pos).unsafe_chr == '%'
        action, nesting = handle_branch_control(nesting, stop_on_else, process: false)
        return if action == :stop
      end
    end
  end

  # Handle control characters within a conditional branch.
  private def handle_branch_control(nesting : Int32, stop_on_else : Bool, process : Bool) : Tuple(Symbol, Int32)
    @pos += 1
    return {:stop, nesting} if @pos >= @format_size

    ctrl = @format.byte_at(@pos).unsafe_chr
    case ctrl
    when '?'
      {:continue, nesting + 1}
    when ';'
      new_nesting = nesting - 1
      new_nesting == 0 ? {:stop, new_nesting} : {:continue, new_nesting}
    when 'e'
      (stop_on_else && nesting == 1) ? {:stop, nesting} : {:continue, nesting}
    else
      if process
        @pos -= 1
        process_escape
      end
      {:continue, nesting}
    end
  end
end
