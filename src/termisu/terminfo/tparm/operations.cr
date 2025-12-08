# Operations lookup tables for tparm processor.
#
# This module provides dispatch tables for the tparm stack machine.
# The terminfo parametrized string format uses a stack-based language where
# operations pop operands from the stack, compute results, and push them back.
#
# ## Operation Categories
#
# - **Binary**: Two-operand operations (arithmetic, bitwise, comparison, logical)
# - **Output**: Format and output the top of stack (%d, %s, %c, %%)
# - **Variable**: Parameter access (%p), variable storage (%P), retrieval (%g)
# - **Constant**: Push literal values (%{n}, %'c')
# - **Special**: Control flow (%?), increment (%i), unary ops (%!, %~, %l)
#
# ## Performance
#
# Optimized for high-frequency operations like cursor positioning (cup) and
# color setting (setaf/setab) which are called thousands of times per frame.
module Termisu::Terminfo::Tparm::Operations
  # Binary operations - arithmetic, bitwise, comparison, logical.
  #
  # All binary ops pop two values (right first, then left), compute, and push result.
  # Division and modulo return 0 on divide-by-zero to prevent crashes.
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

  # Output format operations - pop and write to output buffer.
  OUTPUT_OPS = Set{'%', 'c', 'd', 's'}

  # Variable operations - parameter push and variable get/set.
  VARIABLE_OPS = Set{'p', 'P', 'g'}

  # Constant operations - push literal integer or character values.
  CONSTANT_OPS = Set{'\'', '{'}

  # Special operations - control flow, unary operations, and special commands.
  SPECIAL_OPS = Set{'i', 'l', '!', '~', '?'}

  # All non-binary operation characters for fast membership testing.
  # Used to quickly determine if a character is a known operation.
  ALL_OPS = OUTPUT_OPS | VARIABLE_OPS | CONSTANT_OPS | SPECIAL_OPS
end
