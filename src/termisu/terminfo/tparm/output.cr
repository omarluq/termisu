# Output and unary operations for tparm processor.
#
# Handles output formatting (%d, %c, %s) and unary operations (%l, %!, %~).
module Termisu::Terminfo::Tparm::Output
  # %c - Pop value and output as ASCII character.
  @[AlwaysInline]
  private def output_char
    @output << pop.to_i.unsafe_chr
  end

  # %d - Pop value and output as decimal integer.
  @[AlwaysInline]
  private def output_decimal
    @output << pop.to_s
  end

  # %s - Pop value and output as string.
  @[AlwaysInline]
  private def output_string
    @output << pop.to_s
  end

  # %l - Pop value, convert to string, push its length.
  @[AlwaysInline]
  private def push_length
    push(pop.to_s.size.to_i64)
  end

  # %! - Logical NOT: push 1 if top is 0, else push 0.
  @[AlwaysInline]
  private def push_logical_not
    push(pop == 0 ? 1_i64 : 0_i64)
  end

  # %~ - Bitwise complement.
  @[AlwaysInline]
  private def push_bitwise_not
    push(~pop)
  end
end
