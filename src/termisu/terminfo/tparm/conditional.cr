# Conditional processing for tparm processor.
#
# Handles recursively nested %? ... %t ... %e ... %; constructs. A selected
# branch is interpreted normally, while an unselected branch is scanned with
# nesting awareness so its operations cannot affect the stack or output.
module Termisu::Terminfo::Tparm::Conditional
  # %? - Evaluate the condition and process exactly one branch.
  #
  # Entry and exit follow Processor's cursor convention: @pos points at the
  # operation character. On return it points at this conditional's closing ';'.
  private def process_conditional
    process_conditional_tail(evaluate_condition)
  end

  # Process branches after a %t. ncurses commonly encodes an else-if as
  # `%e <expression> %t ...` without another `%?`; process_conditional_branch
  # calls this method again when it encounters that nested `%t`.
  private def process_conditional_tail(condition : Bool)
    if condition
      control = process_conditional_branch
      skip_conditional_branch(stop_on_else: false) if control == 'e'
    else
      control = skip_conditional_branch(stop_on_else: true)
      process_conditional_branch if control == 'e'
    end
  end

  # Interpret the expression between %? and %t, leaving @pos on the 't'.
  private def evaluate_condition : Bool
    while @pos < @format_size
      @pos += 1
      return false if @pos >= @format_size

      next unless @format.byte_at(@pos).unsafe_chr == '%'

      if @pos + 1 < @format_size && @format.byte_at(@pos + 1).unsafe_chr == 't'
        @pos += 1
        return pop != 0
      end

      process_escape
    end

    false
  end

  # Interpret a selected then/else branch. Nested conditionals are dispatched
  # through process_escape and consume their own closing %; recursively.
  private def process_conditional_branch : Char?
    while @pos < @format_size
      @pos += 1
      return nil if @pos >= @format_size

      if @format.byte_at(@pos).unsafe_chr == '%'
        if @pos + 1 < @format_size
          control = @format.byte_at(@pos + 1).unsafe_chr
          if control == 'e' || control == ';'
            @pos += 1
            return control
          elsif control == 't'
            @pos += 1
            process_conditional_tail(pop != 0)
            return ';'
          end
        end
        process_escape
      else
        @output.write_byte(@format.byte_at(@pos))
      end
    end

    nil
  end

  # Scan an unselected branch without evaluating it. Only conditional control
  # markers matter; nested %e/%; markers are ignored until their matching %?.
  private def skip_conditional_branch(stop_on_else : Bool) : Char?
    nesting = 0

    while @pos < @format_size
      @pos += 1
      return nil if @pos >= @format_size
      next unless @format.byte_at(@pos).unsafe_chr == '%'
      next if @pos + 1 >= @format_size

      control = @format.byte_at(@pos + 1).unsafe_chr
      case control
      when '?'
        nesting += 1
      when ';'
        if nesting == 0
          @pos += 1
          return control
        end
        nesting -= 1
      when 'e'
        if nesting == 0 && stop_on_else
          @pos += 1
          return control
        end
      end

      @pos += 1
    end

    nil
  end
end
