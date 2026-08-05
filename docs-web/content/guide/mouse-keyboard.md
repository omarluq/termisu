+++
title = "Mouse and Keyboard"
description = "Input feature toggles for mouse tracking and enhanced keyboard mode."
weight = 60
+++

# Mouse and Keyboard

## Mouse

```crystal
termisu.enable_mouse
termisu.disable_mouse
termisu.mouse_enabled?
```

## Enhanced Keyboard

```crystal
termisu.enable_enhanced_keyboard
termisu.disable_enhanced_keyboard
termisu.enhanced_keyboard?
```

Enhanced keyboard mode helps disambiguate key combos (for example `Tab` vs `Ctrl+I`).

## Bracketed Paste

```crystal
termisu.enable_bracketed_paste
termisu.disable_bracketed_paste
termisu.bracketed_paste?
```

With DEC private mode 2004 on, the terminal wraps pasted text in boundary markers that
arrive as `Key::PasteStart` and `Key::PasteEnd`, and stops translating line endings
inside the paste. Without it a paste is indistinguishable from typing: a pasted CRLF
arrives as the same bytes `Enter` produces, and some terminals map the LF to a second
CR, so one pasted line break looks exactly like two deliberate `Enter` presses.

The bytes between the markers are reported as they arrive — bracketing says *where* the
paste is, it does not normalize what is inside it.

```crystal
pasting = false
termisu.each_event do |event|
  case event
  when Termisu::Event::Key
    case event.key
    when .paste_start? then pasting = true
    when .paste_end?   then pasting = false
    else                    handle(event, pasted: pasting)
    end
  end
end
```

All three modes are also exposed over the C ABI and the JavaScript binding
(`enableBracketedPaste`, `disableBracketedPaste`, `bracketedPaste`).
