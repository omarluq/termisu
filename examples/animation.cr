require "../src/termisu"

# Simple animation using the async event system with timer ticks.
# Press 'q' or Escape to quit.

termisu = Termisu.new

begin
  width, height = termisu.size
  termisu.enable_timer(16.milliseconds) # ~60 FPS

  # Bouncing ball state
  ball_x, ball_y = width // 2, height // 2
  vel_x, vel_y = 1, 1
  frame = 0

  termisu.each_event do |event|
    case event
    when Termisu::Event::Key
      break if event.key.escape? || event.key.lower_q?
    when Termisu::Event::Resize
      width, height = event.width, event.height
      termisu.sync
    when Termisu::Event::Tick
      frame += 1

      # Clear previous ball position
      termisu.clear

      # Update ball position
      ball_x += vel_x
      ball_y += vel_y

      # Bounce off walls
      if ball_x <= 0 || ball_x >= width - 1
        vel_x = -vel_x
        ball_x = ball_x.clamp(0, width - 1)
      end
      if ball_y <= 0 || ball_y >= height - 2
        vel_y = -vel_y
        ball_y = ball_y.clamp(0, height - 2)
      end

      # Draw ball with trail effect
      termisu.set_cell(ball_x, ball_y, '●', fg: Termisu::Color.cyan, attr: Termisu::Attribute::Bold)

      # Draw frame counter
      status = "Frame: #{frame} | Ball: #{ball_x},#{ball_y} | Press 'q' to quit"
      status.each_char_with_index do |char, idx|
        termisu.set_cell(idx, height - 1, char, fg: Termisu::Color.ansi256(245))
      end

      termisu.render
    end
  end
ensure
  termisu.close
end
