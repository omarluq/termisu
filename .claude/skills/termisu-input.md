# Termisu Input Handling

Keyboard, mouse, and input mode patterns for Termisu TUI applications.

## When to Use

- "Handle keyboard shortcuts"
- "Key binding system"
- "Input mode switching"
- "Mouse interaction"
- "Distinguish keys"
- "Text input field"

## Key Input Patterns

### Basic Key Handling

```crystal
when Termisu::Event::Key
  key = event.key

  # Special keys
  case key
  when .escape? then quit
  when .enter?  then submit
  when .tab?    then next_field
  when .backspace? then delete_char
  end

  # Character input
  if char = key.char
    insert_char(char)
  end
end
```

### Key Binding System

```crystal
class KeyBindings
  @bindings = Hash(Input::Key, Proc).new

  def bind(key : Input::Key, &action : Proc)
    @bindings[key] = action
  end

  def bind(key : String, &action : Proc)
    @bindings[Input::Key.new(key)] = action
  end

  def handle(event : Termisu::Event::Key) : Bool
    key = event.key
    if action = @bindings[key]?
      action.call
      true
    else
      false
    end
  end
end

# Usage
bindings = KeyBindings.new
bindings.bind("q") { quit }
bindings.bind(Input::Key::Escape) { quit }
bindings.bind("Ctrl+c") { quit }  # With enhanced keyboard

# In event loop
when Termisu::Event::Key
  next if bindings.handle(event)
  # Handle unbound keys...
end
```

### Modal Key Bindings

```crystal
class Mode
  property name : String
  property bindings : KeyBindings

  def initialize(@name)
    @bindings = KeyBindings.new
  end

  def bind(key, &action)
    @bindings.bind(key, &action)
  end
end

class InputMode
  @modes = Hash(String, Mode).new
  @current_mode : Mode? = nil

  def define_mode(name : String)
    mode = Mode.new(name)
    @modes[name] = mode
    mode
  end

  def enter_mode(name : String)
    @current_mode = @modes[name]?
  end

  def handle(event : Termisu::Event::Key) : Bool
    @current_mode.try(&.bindings.handle(event)) || false
  end
end

# Usage
modes = InputMode.new

normal = modes.define_mode("normal")
normal.bind("j") { move_cursor(0, 1) }
normal.bind("k") { move_cursor(0, -1) }

insert = modes.define_mode("insert")
insert.bind(Input::Key::Escape) { modes.enter_mode("normal") }

modes.enter_mode("normal")

# In event loop
when Termisu::Event::Key
  next if modes.handle(event)
end
```

### Enhanced Keyboard for Modifiers

```crystal
# Enable to distinguish Tab from Ctrl+I
termisu.enable_enhanced_keyboard

# Now handle precisely
case event.key
when .tab?
  # Definitely Tab, not Ctrl+I
when .ctrl?
  if char = event.key.char
    case char
    when 'c' then handle_ctrl_c
    when 'i' then handle_ctrl_i  # Distinct from Tab!
    end
  end
end
```

### Modifier Combinations

```crystal
# Build modifier description
describe_key(event.key) do |key|
  parts = [] of String
  parts << "Ctrl+" if key.ctrl?
  parts << "Alt+" if key.alt?
  parts << "Shift+" if key.shift?
  parts << key.to_s
  parts.join
end

# Examples output: "Ctrl+Shift+A", "Alt+Enter"
```

## Text Input Patterns

### Single Line Input

```crystal
class TextInput
  property text : String = ""
  property cursor : Int32 = 0
  property position : Tuple(Int32, Int32) {0, 0}

  def handle_key(event : Termisu::Event::Key) : Bool
    key = event.key

    case key
    when .char?
      if char = key.char
        @text = @text.insert(@cursor, char)
        @cursor += 1
        return true
      end

    when .backspace?
      if @cursor > 0
        @text = @text[0...@cursor-1] + @text[@cursor..]
        @cursor -= 1
      end
      return true

    when .left?
      @cursor = (@cursor - 1).clamp(0, @text.size)
      return true

    when .right?
      @cursor = (@cursor + 1).clamp(0, @text.size)
      return true

    when .home?
      @cursor = 0
      return true

    when .end?
      @cursor = @text.size
      return true
    end

    false
  end

  def render(termisu)
    x, y = @position

    # Clear line
    (x...(x + @text.size + 1)).each do |i|
      termisu.set_cell(i, y, ' ')
    end

    # Draw text
    @text.each_char_with_index do |char, idx|
      termisu.set_cell(x + idx, y, char)
    end

    # Draw cursor
    termisu.set_cursor(x + @cursor, y)
  end
end
```

### Password Input

```crystal
password = termisu.with_password_mode do
  print "Password: "
  gets.try(&.chomp)
end
```

### Multi-line Text Area

```crystal
class TextArea
  property lines : Array(String) = [""]
  property cursor_x : Int32 = 0
  property cursor_y : Int32 = 0
  property position : Tuple(Int32, Int32) {0, 0}
  @scroll_y : Int32 = 0

  def handle_key(event : Termisu::Event::Key) : Bool
    key = event.key

    case key
    when .char?
      if char = key.char
        case char
        when '\n'
          @lines.insert(@cursor_y + 1, @lines[@cursor_y][@cursor_x..])
          @lines[@cursor_y] = @lines[@cursor_y][0...@cursor_x]
          @cursor_y += 1
          @cursor_x = 0
        else
          @lines[@cursor_y] = @lines[@cursor_y].insert(@cursor_x, char)
          @cursor_x += 1
        end
        return true
      end

    when .backspace?
      if @cursor_x > 0
        @lines[@cursor_y] = @lines[@cursor_y][0...@cursor_x-1] + @lines[@cursor_y][@cursor_x..]
        @cursor_x -= 1
      elsif @cursor_y > 0
        # Join with previous line
        @cursor_x = @lines[@cursor_y - 1].size
        @lines[@cursor_y - 1] += @lines[@cursor_y]
        @lines.delete_at(@cursor_y)
        @cursor_y -= 1
      end
      return true

    when .up?
      @cursor_y = (@cursor_y - 1).clamp(0, @lines.size - 1)
      @cursor_x = @cursor_x.clamp(0, @lines[@cursor_y].size)
      return true

    when .down?
      @cursor_y = (@cursor_y + 1).clamp(0, @lines.size - 1)
      @cursor_x = @cursor_x.clamp(0, @lines[@cursor_y].size)
      return true
    end

    false
  end
end
```

## Mouse Patterns

### Clickable Areas

```crystal
class Clickable
  property rect : Tuple(Int32, Int32, Int32, Int32)  # x, y, w, h
  property action : Proc(Termisu::Event::Mouse, Nil)

  def initialize(@x, @y, @width, @height, &@action)
  end

  def contains?(x, y) : Bool
    x >= @x && x < @x + @width && y >= @y && y < @y + @height
  end

  def handle(event : Termisu::Event::Mouse) : Bool
    if contains?(event.x, event.y) && event.press?
      @action.call(event)
      true
    else
      false
    end
  end
end

# Usage
clickables = [] of Clickable

clickables << Clickable.new(10, 5, 20, 3) do |event|
  if event.button == Mouse::Button::Left
    submit_form
  end
end

# In event loop
when Termisu::Event::Mouse
  clickables.any?(&.handle(event))
end
```

### Scrollable List

```crystal
class ScrollList(T)
  @items : Array(T)
  @selected : Int32 = 0
  @scroll : Int32 = 0
  @position : Tuple(Int32, Int32)
  @visible_rows : Int32

  def initialize(@items, @x, @y, @visible_rows)
    @position = {@x, @y}
  end

  def handle_key(event : Termisu::Event::Key) : Bool
    key = event.key

    case key
    when .up?
      @selected = (@selected - 1).clamp(0, @items.size - 1)
      update_scroll
      return true

    when .down?
      @selected = (@selected + 1).clamp(0, @items.size - 1)
      update_scroll
      return true
    end

    false
  end

  def handle_mouse(event : Termisu::Event::Mouse) : Bool
    x, y = @position

    # Check if mouse is over list
    if event.x >= x && event.x < x + 20 && event.y >= y && event.y < y + @visible_rows
      if event.wheel?
        if event.button == Mouse::Wheel::Up
          @selected = (@selected - 1).clamp(0, @items.size - 1)
          update_scroll
        elsif event.button == Mouse::Wheel::Down
          @selected = (@selected + 1).clamp(0, @items.size - 1)
          update_scroll
        end
        return true
      elsif event.press?
        @selected = @scroll + (event.y - y)
        @selected = @selected.clamp(0, @items.size - 1)
        return true
      end
    end

    false
  end

  private def update_scroll
    if @selected < @scroll
      @scroll = @selected
    elsif @selected >= @scroll + @visible_rows
      @scroll = @selected - @visible_rows + 1
    end
  end
end
```

### Drag Handling

```crystal
class Draggable
  @dragging = false
  @start_x = 0
  @start_y = 0
  @value = 0

  def handle_mouse(event : Termisu::Event::Mouse) : Bool
    case event
    when .press?
      @dragging = true
      @start_x = event.x
      @start_y = event.y
      return true

    when .motion?
      if @dragging
        dx = event.x - @start_x
        @value += dx
        @start_x = event.x
        return true
      end

    when .release?
      @dragging = false
      return true
    end

    false
  end
end
```

## Input Mode Switching

### Vi-like Modes

```crystal
enum Mode
  Normal
  Insert
  Visual
  Command
end

class ViInput
  property mode : Mode = Mode::Normal

  def handle_key(event : Termisu::Event::Key, termisu) : Bool
    case @mode
    in Mode::Normal
      handle_normal(event)
    in Mode::Insert
      handle_insert(event)
    in Mode::Visual
      handle_visual(event)
    in Mode::Command
      handle_command(event)
    end
  end

  private def handle_normal(event)
    key = event.key

    case key
    when .char?('i') then @mode = Mode::Insert
    when .char?('v') then @mode = Mode::Visual
    when .char?(':') then @mode = Mode::Command
    when .char?('j') then move_down
    when .char?('k') then move_up
    when .char?('h') then move_left
    when .char?('l') then move_right
    else false
    end
  end

  private def handle_insert(event)
    key = event.key

    case key
    when .escape? then @mode = Mode::Normal
    when .char? then insert_char(key.char)
    else false
    end
  end
end
```

### Emacs-like Key Chords

```crystal
class EmacsBindings
  @pending_escape = false
  @pending_ctrl_x = false

  def handle_key(event : Termisu::Event::Key) : Bool
    key = event.key

    # Ctrl+X prefix
    if key.ctrl? && key.char == 'x'
      @pending_ctrl_x = true
      return true
    end

    if @pending_ctrl_x
      @pending_ctrl_x = false
      case key
      when .char?('c') then quit
      when .char?('s') then save
      when .char?('f') then find_file
      else false
      end
      return true
    end

    # ESC prefix (meta)
    if key.escape?
      @pending_escape = true
      return true
    end

    if @pending_escape
      @pending_escape = false
      # Meta+key combinations
      if char = key.char
        case char
        when 'x' then execute_command
        when 'f' then forward_word
        when 'b' then backward_word
        else false
        end
        return true
      end
    end

    false
  end
end
```

## Quick Reference

| Task | Pattern |
|------|---------|
| Key binding | Hash(Input::Key, Proc) |
| Modal input | Mode → KeyBindings |
| Text input | Track cursor position in string |
| Password | `termisu.with_password_mode` |
| Mouse click | Check x,y in bounds |
| Scroll | Update offset based on wheel |
| Drag | Track press, motion, release |
| Enhanced keyboard | `termisu.enable_enhanced_keyboard` |
