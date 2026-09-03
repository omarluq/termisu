require "../../src/termisu"

Termisu::Logging.setup
500.times do |number|
  Termisu::Log.info { "exit-numbered-#{number}" }
end
