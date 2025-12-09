require "../src/termisu"

# Interactive keyboard & mouse demo - press keys and click to see events!
# Press ESC or Ctrl+C to quit.
#
# Features:
#   - Visual keyboard with key highlighting
#   - Mouse tracking (clicks, wheel, movement)
#   - Modifier key detection (Ctrl, Alt, Shift, Meta)
#   - Function keys and navigation keys
#
# To enable debug logging:
#   TERMISU_LOG_LEVEL=debug TERMISU_LOG_FILE=/tmp/keyboard.log crystal run examples/keyboard.cr

termisu = Termisu.new
Termisu::Log.info { "Keyboard & Mouse demo started" }

begin
  termisu.enable_mouse
  termisu.enable_enhanced_keyboard # Enable Kitty/modifyOtherKeys protocols
  width, height = termisu.size

  # Keyboard layout (US QWERTY)
  rows = [
    {
      keys:   ["Esc", "`", "1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "-", "=", "⌫"],
      widths: [5, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 6],
    },
    {
      keys:   ["⇥", "Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P", "[", "]", "\\"],
      widths: [6, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 6],
    },
    {
      keys:   ["⇪", "A", "S", "D", "F", "G", "H", "J", "K", "L", ";", "'", "⏎"],
      widths: [7, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 9],
    },
    {
      keys:   ["⇧", "Z", "X", "C", "V", "B", "N", "M", ",", ".", "/", "⇧"],
      widths: [9, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 11],
    },
    {
      keys:   ["Ctrl", "Alt", "␣", "Alt", "Ctrl"],
      widths: [8, 8, 30, 8, 8],
    },
  ]

  # Map Key enum values to row/key index for highlighting
  key_positions = {} of Termisu::Input::Key => {Int32, Int32}

  # Row 0: Escape, number row, backspace
  key_positions[Termisu::Input::Key::Escape] = {0, 0}
  key_positions[Termisu::Input::Key::Backtick] = {0, 1}
  key_positions[Termisu::Input::Key::Tilde] = {0, 1}
  key_positions[Termisu::Input::Key::Num1] = {0, 2}
  key_positions[Termisu::Input::Key::Exclaim] = {0, 2}
  key_positions[Termisu::Input::Key::Num2] = {0, 3}
  key_positions[Termisu::Input::Key::At] = {0, 3}
  key_positions[Termisu::Input::Key::Num3] = {0, 4}
  key_positions[Termisu::Input::Key::Hash] = {0, 4}
  key_positions[Termisu::Input::Key::Num4] = {0, 5}
  key_positions[Termisu::Input::Key::Dollar] = {0, 5}
  key_positions[Termisu::Input::Key::Num5] = {0, 6}
  key_positions[Termisu::Input::Key::Percent] = {0, 6}
  key_positions[Termisu::Input::Key::Num6] = {0, 7}
  key_positions[Termisu::Input::Key::Caret] = {0, 7}
  key_positions[Termisu::Input::Key::Num7] = {0, 8}
  key_positions[Termisu::Input::Key::Ampersand] = {0, 8}
  key_positions[Termisu::Input::Key::Num8] = {0, 9}
  key_positions[Termisu::Input::Key::Asterisk] = {0, 9}
  key_positions[Termisu::Input::Key::Num9] = {0, 10}
  key_positions[Termisu::Input::Key::LeftParen] = {0, 10}
  key_positions[Termisu::Input::Key::Num0] = {0, 11}
  key_positions[Termisu::Input::Key::RightParen] = {0, 11}
  key_positions[Termisu::Input::Key::Minus] = {0, 12}
  key_positions[Termisu::Input::Key::Underscore] = {0, 12}
  key_positions[Termisu::Input::Key::Equals] = {0, 13}
  key_positions[Termisu::Input::Key::Plus] = {0, 13}
  key_positions[Termisu::Input::Key::Backspace] = {0, 14}

  # Row 1: Tab, QWERTY row
  key_positions[Termisu::Input::Key::Tab] = {1, 0}
  key_positions[Termisu::Input::Key::UpperQ] = {1, 1}
  key_positions[Termisu::Input::Key::LowerQ] = {1, 1}
  key_positions[Termisu::Input::Key::UpperW] = {1, 2}
  key_positions[Termisu::Input::Key::LowerW] = {1, 2}
  key_positions[Termisu::Input::Key::UpperE] = {1, 3}
  key_positions[Termisu::Input::Key::LowerE] = {1, 3}
  key_positions[Termisu::Input::Key::UpperR] = {1, 4}
  key_positions[Termisu::Input::Key::LowerR] = {1, 4}
  key_positions[Termisu::Input::Key::UpperT] = {1, 5}
  key_positions[Termisu::Input::Key::LowerT] = {1, 5}
  key_positions[Termisu::Input::Key::UpperY] = {1, 6}
  key_positions[Termisu::Input::Key::LowerY] = {1, 6}
  key_positions[Termisu::Input::Key::UpperU] = {1, 7}
  key_positions[Termisu::Input::Key::LowerU] = {1, 7}
  key_positions[Termisu::Input::Key::UpperI] = {1, 8}
  key_positions[Termisu::Input::Key::LowerI] = {1, 8}
  key_positions[Termisu::Input::Key::UpperO] = {1, 9}
  key_positions[Termisu::Input::Key::LowerO] = {1, 9}
  key_positions[Termisu::Input::Key::UpperP] = {1, 10}
  key_positions[Termisu::Input::Key::LowerP] = {1, 10}
  key_positions[Termisu::Input::Key::LeftBracket] = {1, 11}
  key_positions[Termisu::Input::Key::LeftBrace] = {1, 11}
  key_positions[Termisu::Input::Key::RightBracket] = {1, 12}
  key_positions[Termisu::Input::Key::RightBrace] = {1, 12}
  key_positions[Termisu::Input::Key::Backslash] = {1, 13}
  key_positions[Termisu::Input::Key::Pipe] = {1, 13}

  # Row 2: Caps, ASDF row, Enter
  key_positions[Termisu::Input::Key::UpperA] = {2, 1}
  key_positions[Termisu::Input::Key::LowerA] = {2, 1}
  key_positions[Termisu::Input::Key::UpperS] = {2, 2}
  key_positions[Termisu::Input::Key::LowerS] = {2, 2}
  key_positions[Termisu::Input::Key::UpperD] = {2, 3}
  key_positions[Termisu::Input::Key::LowerD] = {2, 3}
  key_positions[Termisu::Input::Key::UpperF] = {2, 4}
  key_positions[Termisu::Input::Key::LowerF] = {2, 4}
  key_positions[Termisu::Input::Key::UpperG] = {2, 5}
  key_positions[Termisu::Input::Key::LowerG] = {2, 5}
  key_positions[Termisu::Input::Key::UpperH] = {2, 6}
  key_positions[Termisu::Input::Key::LowerH] = {2, 6}
  key_positions[Termisu::Input::Key::UpperJ] = {2, 7}
  key_positions[Termisu::Input::Key::LowerJ] = {2, 7}
  key_positions[Termisu::Input::Key::UpperK] = {2, 8}
  key_positions[Termisu::Input::Key::LowerK] = {2, 8}
  key_positions[Termisu::Input::Key::UpperL] = {2, 9}
  key_positions[Termisu::Input::Key::LowerL] = {2, 9}
  key_positions[Termisu::Input::Key::Semicolon] = {2, 10}
  key_positions[Termisu::Input::Key::Colon] = {2, 10}
  key_positions[Termisu::Input::Key::Quote] = {2, 11}
  key_positions[Termisu::Input::Key::DoubleQuote] = {2, 11}
  key_positions[Termisu::Input::Key::Enter] = {2, 12}

  # Row 3: Shift, ZXCV row
  key_positions[Termisu::Input::Key::UpperZ] = {3, 1}
  key_positions[Termisu::Input::Key::LowerZ] = {3, 1}
  key_positions[Termisu::Input::Key::UpperX] = {3, 2}
  key_positions[Termisu::Input::Key::LowerX] = {3, 2}
  key_positions[Termisu::Input::Key::UpperC] = {3, 3}
  key_positions[Termisu::Input::Key::LowerC] = {3, 3}
  key_positions[Termisu::Input::Key::UpperV] = {3, 4}
  key_positions[Termisu::Input::Key::LowerV] = {3, 4}
  key_positions[Termisu::Input::Key::UpperB] = {3, 5}
  key_positions[Termisu::Input::Key::LowerB] = {3, 5}
  key_positions[Termisu::Input::Key::UpperN] = {3, 6}
  key_positions[Termisu::Input::Key::LowerN] = {3, 6}
  key_positions[Termisu::Input::Key::UpperM] = {3, 7}
  key_positions[Termisu::Input::Key::LowerM] = {3, 7}
  key_positions[Termisu::Input::Key::Comma] = {3, 8}
  key_positions[Termisu::Input::Key::LessThan] = {3, 8}
  key_positions[Termisu::Input::Key::Period] = {3, 9}
  key_positions[Termisu::Input::Key::GreaterThan] = {3, 9}
  key_positions[Termisu::Input::Key::Slash] = {3, 10}
  key_positions[Termisu::Input::Key::Question] = {3, 10}

  # Row 4: Space bar
  key_positions[Termisu::Input::Key::Space] = {4, 2}

  # Track state
  highlighted : {Int32, Int32}? = nil
  current_modifiers = Termisu::Input::Modifier::None
  last_event_text = ""
  mouse_x = 0
  mouse_y = 0
  mouse_button = ""

  # Calculate keyboard position (centered)
  kb_width = 62
  kb_height = rows.size * 3
  start_x = [(width - kb_width) // 2, 0].max
  start_y = [(height - kb_height - 10) // 2, 2].max

  # Draw text helper
  draw_text = ->(x : Int32, y : Int32, text : String, fg : Termisu::Color, bg : Termisu::Color?) do
    text.each_char_with_index do |char, idx|
      if bg
        termisu.set_cell(x + idx, y, char, fg: fg, bg: bg)
      else
        termisu.set_cell(x + idx, y, char, fg: fg)
      end
    end
  end

  # Draw title
  title = "⌨ KEYBOARD & MOUSE DEMO ⌨"
  title_x = [(width - title.size) // 2, 0].max
  draw_text.call(title_x, start_y - 2, title, Termisu::Color.cyan, nil)

  # Draw keyboard function
  draw_keyboard = ->(hl : {Int32, Int32}?, mods : Termisu::Input::Modifier) do
    current_y = start_y

    rows.each_with_index do |row, row_idx|
      current_x = start_x

      row[:keys].each_with_index do |key, key_idx|
        key_width = row[:widths][key_idx]
        is_highlighted = hl == {row_idx, key_idx}

        # Check if this is a modifier key that's currently active
        is_mod_active = case key
                        when "Ctrl" then mods.ctrl?
                        when "Alt"  then mods.alt?
                        when "⇧"    then mods.shift?
                        else             false
                        end

        # Colors
        fg = (is_highlighted || is_mod_active) ? Termisu::Color.black : Termisu::Color.white
        bg = if is_highlighted
               Termisu::Color.yellow
             elsif is_mod_active
               Termisu::Color.magenta
             else
               Termisu::Color.ansi256(236)
             end
        border_fg = if is_highlighted
                      Termisu::Color.yellow
                    elsif is_mod_active
                      Termisu::Color.magenta
                    else
                      Termisu::Color.ansi256(240)
                    end

        # Draw key box (3 rows tall)
        # Top border
        termisu.set_cell(current_x, current_y, '┌', fg: border_fg)
        (key_width - 2).times do |idx|
          termisu.set_cell(current_x + 1 + idx, current_y, '─', fg: border_fg)
        end
        termisu.set_cell(current_x + key_width - 1, current_y, '┐', fg: border_fg)

        # Middle row with key label
        termisu.set_cell(current_x, current_y + 1, '│', fg: border_fg)
        (key_width - 2).times do |idx|
          termisu.set_cell(current_x + 1 + idx, current_y + 1, ' ', bg: bg)
        end
        # Center the key label
        display_width = key.each_char.size
        label_x = current_x + 1 + (key_width - 2 - display_width) // 2
        key.each_char_with_index do |char, idx|
          termisu.set_cell(label_x + idx, current_y + 1, char, fg: fg, bg: bg)
        end
        termisu.set_cell(current_x + key_width - 1, current_y + 1, '│', fg: border_fg)

        # Bottom border
        termisu.set_cell(current_x, current_y + 2, '└', fg: border_fg)
        (key_width - 2).times do |idx|
          termisu.set_cell(current_x + 1 + idx, current_y + 2, '─', fg: border_fg)
        end
        termisu.set_cell(current_x + key_width - 1, current_y + 2, '┘', fg: border_fg)

        current_x += key_width
      end

      current_y += 3
    end
  end

  # Draw mouse info panel
  draw_mouse_panel = ->(mx : Int32, my : Int32, btn : String) do
    panel_y = start_y + kb_height + 1
    panel_x = start_x

    # Clear previous content
    60.times { |idx| termisu.set_cell(panel_x + idx, panel_y, ' ') }
    60.times { |idx| termisu.set_cell(panel_x + idx, panel_y + 1, ' ') }

    # Draw mouse info
    draw_text.call(panel_x, panel_y, "🖱 Mouse:", Termisu::Color.cyan, nil)
    pos_text = "Position: (#{mx}, #{my})"
    draw_text.call(panel_x + 10, panel_y, pos_text, Termisu::Color.green, nil)

    if !btn.empty?
      draw_text.call(panel_x + 30, panel_y, btn, Termisu::Color.yellow, nil)
    end
  end

  # Draw event log
  draw_event_log = ->(text : String) do
    log_y = start_y + kb_height + 3
    # Clear line
    70.times { |idx| termisu.set_cell(start_x + idx, log_y, ' ') }
    draw_text.call(start_x, log_y, "Last event: ", Termisu::Color.white, nil)
    draw_text.call(start_x + 12, log_y, text, Termisu::Color.green, nil)
  end

  # Draw help text
  status_y = start_y + kb_height + 5
  hint = "Press keys to highlight | Click/scroll anywhere | ESC or Ctrl+C to quit"
  hint_x = [(width - hint.size) // 2, 0].max
  draw_text.call(hint_x, status_y, hint, Termisu::Color.ansi256(245), nil)

  # Initial draw
  draw_keyboard.call(nil, Termisu::Input::Modifier::None)
  draw_mouse_panel.call(0, 0, "")
  termisu.render

  # Main loop using event-based input
  Termisu::Log.debug { "Entering main loop, terminal size: #{width}x#{height}" }

  loop do
    if event = termisu.poll_event(50)
      Termisu::Log.debug { "Received event: #{event.class}" }

      case event
      when Termisu::Event::Key
        key_event = event.as(Termisu::Event::Key)

        # Quit on ESC or Ctrl+C
        if key_event.key.escape? || key_event.ctrl_c?
          Termisu::Log.info { "Quit requested" }
          break
        end

        # Find key position for highlighting
        highlighted = key_positions[key_event.key]?
        current_modifiers = key_event.modifiers

        # Build event description
        parts = [] of String
        parts << "Ctrl+" if key_event.ctrl?
        parts << "Alt+" if key_event.alt?
        parts << "Shift+" if key_event.shift?
        parts << "Meta+" if key_event.meta?
        parts << key_event.key.to_s

        # Show alternate interpretation for ambiguous keys
        # (Terminal can't distinguish Tab vs Ctrl+I, Enter vs Ctrl+M, etc.)
        case key_event.key
        when .tab?
          parts << " (=Ctrl+I)"
        when .enter?
          parts << " (=Ctrl+M)"
        when .backspace?
          parts << " (=Ctrl+H or DEL)"
        else
          if char = key_event.char
            parts << " ('#{char}')" if char.printable?
          end
        end

        last_event_text = parts.join

        # Redraw
        draw_keyboard.call(highlighted, current_modifiers)
        draw_event_log.call(last_event_text)
        termisu.render
      when Termisu::Event::Mouse
        mouse_event = event.as(Termisu::Event::Mouse)

        mouse_x = mouse_event.x
        mouse_y = mouse_event.y

        # Build button description
        btn_parts = [] of String
        btn_parts << "Ctrl+" if mouse_event.ctrl?
        btn_parts << "Alt+" if mouse_event.alt?
        btn_parts << "Shift+" if mouse_event.shift?

        if mouse_event.motion?
          if mouse_event.button.release?
            btn_parts << "Hover"
          else
            btn_parts << "Drag(#{mouse_event.button})"
          end
        elsif mouse_event.wheel?
          btn_parts << mouse_event.button.to_s
        elsif mouse_event.press?
          btn_parts << "#{mouse_event.button} click"
        else
          btn_parts << "#{mouse_event.button} release"
        end

        mouse_button = btn_parts.join

        # Update event log
        last_event_text = "Mouse #{mouse_button} at (#{mouse_x}, #{mouse_y})"

        # Redraw
        draw_mouse_panel.call(mouse_x, mouse_y, mouse_button)
        draw_event_log.call(last_event_text)
        termisu.render
      when Termisu::Event::Resize
        resize_event = event.as(Termisu::Event::Resize)
        width = resize_event.width
        height = resize_event.height

        # Recalculate positions
        start_x = [(width - kb_width) // 2, 0].max
        start_y = [(height - kb_height - 10) // 2, 2].max

        # Force full redraw
        termisu.clear
        draw_keyboard.call(highlighted, current_modifiers)
        draw_mouse_panel.call(mouse_x, mouse_y, mouse_button)
        draw_event_log.call(last_event_text)

        # Redraw title and hint
        title_x = [(width - title.size) // 2, 0].max
        draw_text.call(title_x, start_y - 2, title, Termisu::Color.cyan, nil)
        status_y = start_y + kb_height + 5
        hint_x = [(width - hint.size) // 2, 0].max
        draw_text.call(hint_x, status_y, hint, Termisu::Color.ansi256(245), nil)

        termisu.sync
        last_event_text = "Resize: #{width}x#{height}"
        draw_event_log.call(last_event_text)
        termisu.render
      end
    end
  end
ensure
  Termisu::Log.info { "Keyboard & Mouse demo closing" }
  termisu.disable_enhanced_keyboard
  termisu.disable_mouse
  termisu.close
end
