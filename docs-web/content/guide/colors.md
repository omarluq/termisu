+++
title = "Colors"
description = "Color APIs: ANSI-8, ANSI-256, RGB, and conversions."
weight = 90
+++

# Colors

```crystal
Color.red
Color.bright_green
Color.ansi256(208)
Color.rgb(255, 128, 64)
Color.from_hex("#FF8040")
Color.grayscale(12)
```

## Conversions

```crystal
color.to_rgb
color.to_ansi256
color.to_ansi8
```
