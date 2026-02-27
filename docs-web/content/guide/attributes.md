+++
title = "Attributes"
description = "Text attribute flags and combinations."
weight = 100
+++

# Attributes

```crystal
Termisu::Attribute::None
Termisu::Attribute::Bold
Termisu::Attribute::Dim
Termisu::Attribute::Italic
Termisu::Attribute::Underline
Termisu::Attribute::Blink
Termisu::Attribute::Reverse
Termisu::Attribute::Hidden
Termisu::Attribute::Strikethrough
```

## Combine Flags

```crystal
attr = Termisu::Attribute::Bold | Termisu::Attribute::Underline
```
