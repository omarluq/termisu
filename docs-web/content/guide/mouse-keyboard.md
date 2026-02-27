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
