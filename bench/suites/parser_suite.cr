require "../bench_runner"

module Termisu::Bench
  module ParserSuite
    extend self

    # Create valid mock terminfo data for benchmarking
    def create_mock_data : Bytes
      io = IO::Memory.new

      # Header
      io.write_bytes(0o432_i16, IO::ByteFormat::LittleEndian) # magic
      io.write_bytes(10_i16, IO::ByteFormat::LittleEndian)    # names length
      io.write_bytes(0_i16, IO::ByteFormat::LittleEndian)     # booleans
      io.write_bytes(5_i16, IO::ByteFormat::LittleEndian)     # numbers
      io.write_bytes(50_i16, IO::ByteFormat::LittleEndian)    # string count
      io.write_bytes(250_i16, IO::ByteFormat::LittleEndian)   # string table size

      # Names section
      io.write("xterm-test".to_slice)

      # Numbers section (5 * 2 bytes)
      5.times { io.write_bytes(0_i16, IO::ByteFormat::LittleEndian) }

      # String offset table (50 * 2 bytes)
      50.times do |idx|
        io.write_bytes((idx * 5).to_i16, IO::ByteFormat::LittleEndian)
      end

      # String table (50 strings of "test\0")
      50.times { io.write("test\0".to_slice) }

      io.to_slice
    end

    def run : Array(BenchGroup)
      mock_data = create_mock_data
      groups = [] of BenchGroup

      groups << run_parser_creation(mock_data)
      groups << run_capability_parsing(mock_data)
      groups << run_full_parse_cycle(mock_data)
      groups << run_error_handling(mock_data)

      groups
    end

    private def run_parser_creation(mock_data : Bytes) : BenchGroup
      capture = BenchCapture.new

      capture.report("Parser.new") do
        Terminfo::Parser.new(mock_data)
      end

      BenchGroup.new("Parser Creation", capture.results)
    end

    private def run_capability_parsing(mock_data : Bytes) : BenchGroup
      parser = Terminfo::Parser.new(mock_data)
      capture = BenchCapture.new

      capture.report("parse 1 cap") do
        parser.parse(["clear"])
      end

      capture.report("parse 5 caps") do
        parser.parse(["clear", "bold", "smul", "civis", "cnorm"])
      end

      capture.report("parse 10 caps") do
        parser.parse(["clear", "bold", "smul", "civis", "cnorm",
                      "smcup", "rmcup", "cup", "home", "el"])
      end

      BenchGroup.new("Capability Parsing", capture.results)
    end

    private def run_full_parse_cycle(mock_data : Bytes) : BenchGroup
      capture = BenchCapture.new

      capture.report("Parser.parse (1 cap)") do
        Terminfo::Parser.parse(mock_data, ["clear"])
      end

      capture.report("Parser.parse (5 caps)") do
        Terminfo::Parser.parse(mock_data, ["clear", "bold", "smul", "civis", "cnorm"])
      end

      capture.report("Parser.parse? (safe)") do
        Terminfo::Parser.parse?(mock_data, ["clear", "bold"])
      end

      BenchGroup.new("Full Parse Cycle", capture.results)
    end

    private def run_error_handling(mock_data : Bytes) : BenchGroup
      corrupt_data = Bytes[1, 2, 3]
      invalid_magic = mock_data.clone
      invalid_magic[0] = 0xFF_u8
      invalid_magic[1] = 0xFF_u8

      capture = BenchCapture.new

      capture.report("parse? (corrupt - nil)") do
        Terminfo::Parser.parse?(corrupt_data, ["clear"])
      end

      capture.report("parse? (bad magic - nil)") do
        Terminfo::Parser.parse?(invalid_magic, ["clear"])
      end

      BenchGroup.new("Error Handling", capture.results)
    end
  end
end
