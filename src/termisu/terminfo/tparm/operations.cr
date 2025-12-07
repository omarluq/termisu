# Operations lookup tables for tparm processor.
# Provides O(1) dispatch instead of case branching.
module Termisu::Terminfo::Tparm::Operations
  # Binary operations - arithmetic, bitwise, comparison, logical.
  BINARY = {
    '+' => ->(left : Int64, right : Int64) { left + right },
    '-' => ->(left : Int64, right : Int64) { left - right },
    '*' => ->(left : Int64, right : Int64) { left * right },
    '/' => ->(left : Int64, right : Int64) { right != 0 ? left // right : 0_i64 },
    'm' => ->(left : Int64, right : Int64) { right != 0 ? left % right : 0_i64 },
    '&' => ->(left : Int64, right : Int64) { left & right },
    '|' => ->(left : Int64, right : Int64) { left | right },
    '^' => ->(left : Int64, right : Int64) { left ^ right },
    '=' => ->(left : Int64, right : Int64) { left == right ? 1_i64 : 0_i64 },
    '<' => ->(left : Int64, right : Int64) { left < right ? 1_i64 : 0_i64 },
    '>' => ->(left : Int64, right : Int64) { left > right ? 1_i64 : 0_i64 },
    'A' => ->(left : Int64, right : Int64) { (left != 0 && right != 0) ? 1_i64 : 0_i64 },
    'O' => ->(left : Int64, right : Int64) { (left != 0 || right != 0) ? 1_i64 : 0_i64 },
  }

  # Output format operations.
  OUTPUT_OPS = Set{'%', 'c', 'd', 's'}

  # Variable operations.
  VARIABLE_OPS = Set{'p', 'P', 'g'}

  # Constant operations.
  CONSTANT_OPS = Set{'\'', '{'}

  # Special operations.
  SPECIAL_OPS = Set{'i', 'l', '!', '~', '?'}
end
