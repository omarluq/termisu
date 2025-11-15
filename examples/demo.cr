require "../src/termisu"

termisu = Termisu.new
puts "Running in alternate screen!"
sleep 10.seconds
puts "shutting down"
sleep 1.seconds
termisu.close
