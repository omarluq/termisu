# Test helper classes for spec files.
#
# Contains utility classes that aid in testing but aren't
# mock implementations of production code.
module TestHelpers
  # Helper class to hold mutable size values for testing.
  #
  # Crystal closures capture variables by reference, so modifying
  # these values will affect the size provider proc.
  #
  # Example:
  # ```
  # size = TestHelpers::MutableSize.new(80, 24)
  # provider = -> { size.to_tuple }
  #
  # # Later, change the size
  # size.width = 100
  # size.height = 50
  #
  # # provider.call now returns {100, 50}
  # ```
  class MutableSize
    property width : Int32
    property height : Int32

    def initialize(@width : Int32, @height : Int32)
    end

    def to_tuple : {Int32, Int32}
      {@width, @height}
    end
  end
end
