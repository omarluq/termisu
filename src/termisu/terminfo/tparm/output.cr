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
    # IO#<<(Int64) formats digits directly into the IO without allocating a String.
    @output << pop
  end

  # %s - Pop value and output as string.
  @[AlwaysInline]
  private def output_string
    # IO#<<(Int64) formats digits directly into the IO without allocating a String.
    @output << pop
  end

  # Writes a printf-style conversion parsed by Processor. Integer precision is
  # a minimum digit count; field width pads with spaces unless the zero flag is
  # active. This covers the forms emitted by ncurses' standard capabilities.
  private def output_formatted(
    value : Int64,
    conversion : Char,
    flags : String,
    width : Int32,
    precision : Int32?,
  ) : Nil
    if conversion == 's'
      output_formatted_string(value, flags, width, precision)
    else
      output_formatted_integer(value, conversion, flags, width, precision)
    end
  end

  private def output_formatted_string(value, flags, width, precision) : Nil
    text = value.to_s
    text = text.byte_slice(0, precision) if precision && precision < text.bytesize
    write_padded(text, width, flags.includes?('-'))
  end

  private def output_formatted_integer(value, conversion, flags, width, precision) : Nil
    # ncurses applies unsigned conversions to 32-bit integer values.
    formatted_value = if conversion.in?('o', 'x', 'X')
                        value.to_i32!.to_u32!.to_i64
                      else
                        value
                      end
    sign = formatted_sign(value, conversion, flags)
    digits = formatted_digits(formatted_value, conversion, precision)
    if conversion == 'o' && flags.includes?('#') && !digits.starts_with?('0')
      digits = "0#{digits}"
    end
    prefix = formatted_prefix(formatted_value, conversion, flags)
    text = sign + prefix + digits

    if zero_pad?(flags, precision, text, width)
      @output << sign << prefix << ("0" * (width - text.bytesize)) << digits
    else
      write_padded(text, width, flags.includes?('-'))
    end
  end

  private def formatted_sign(value, conversion, flags) : String
    return "-" if conversion == 'd' && value < 0
    return "+" if conversion == 'd' && flags.includes?('+')
    return " " if conversion == 'd' && flags.includes?(' ')
    ""
  end

  private def formatted_prefix(value, conversion, flags) : String
    return "" unless flags.includes?('#') && value != 0

    case conversion
    when 'x' then "0x"
    when 'X' then "0X"
    else          ""
    end
  end

  private def formatted_digits(value, conversion, precision) : String
    digits = case conversion
             when 'd'
               text = value.to_s
               value < 0 ? text.byte_slice(1) : text
             when 'o'
               value.to_s(8)
             else
               value.to_s(16)
             end
    digits = digits.upcase if conversion == 'X'
    digits = "" if precision == 0 && value == 0
    precision && digits.bytesize < precision ? digits.rjust(precision, '0') : digits
  end

  private def zero_pad?(flags, precision, text, width) : Bool
    flags.includes?('0') && !flags.includes?('-') && precision.nil? && text.bytesize < width
  end

  private def write_padded(text : String, width : Int32, left_aligned : Bool) : Nil
    padding = width - text.bytesize
    if padding > 0
      if left_aligned
        @output << text << (" " * padding)
      else
        @output << (" " * padding) << text
      end
    else
      @output << text
    end
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
