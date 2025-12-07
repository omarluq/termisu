# Base error class for all Termisu exceptions.
class Termisu::Error < Exception
end

# Error raised when parsing terminfo binary data fails.
#
# Provides specific error types to distinguish between different failure modes:
# - Invalid magic number (unsupported format)
# - Truncated data (file too small)
# - Invalid header values
# - Corrupted string table
class Termisu::ParseError < Termisu::Error
  # Specific error type for categorization.
  enum Type
    InvalidMagic    # Magic number not recognized
    TruncatedData   # Data smaller than expected
    InvalidHeader   # Header contains invalid values
    InvalidOffset   # String offset points outside data
    CorruptedString # String table is malformed
  end

  getter type : Type
  getter details : String?

  def initialize(@type : Type, message : String, @details : String? = nil)
    super(message)
  end

  # Creates an InvalidMagic error.
  # Magic numbers: 282 (0o432) for standard, 542 for extended format.
  def self.invalid_magic(actual : Int16) : ParseError
    new(Type::InvalidMagic,
      "Invalid terminfo magic number: #{actual} (expected 282 or 542)",
      "Got 0x#{actual.to_s(16)}")
  end

  # Creates a TruncatedData error.
  def self.truncated_data(expected : Int32, actual : Int32) : ParseError
    new(Type::TruncatedData,
      "Terminfo data truncated: expected at least #{expected} bytes, got #{actual}",
      "Missing #{expected - actual} bytes")
  end

  # Creates an InvalidHeader error.
  def self.invalid_header(field : String, value : Int16) : ParseError
    new(Type::InvalidHeader,
      "Invalid terminfo header: #{field} = #{value}",
      "Negative or unreasonable value")
  end

  # Creates an InvalidOffset error.
  def self.invalid_offset(offset : Int32, max : Int32) : ParseError
    new(Type::InvalidOffset,
      "Invalid string offset: #{offset} exceeds data size #{max}",
      "Offset out of bounds")
  end
end
