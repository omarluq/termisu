+++
title = "Termisu"
description = "Pixel-sharp terminal UI toolkit for Crystal."
+++

<section class="landing-hero">
  <h1>Build terminal apps that feel crisp, fast, and alive.</h1>
  <p class="landing-lead">Termisu gives you a double-buffer renderer, event pipeline, timers, colors, and input modes without heavy framework overhead.</p>
  <div class="landing-cta">
    <a class="landing-btn primary" href="/getting-started/installation/"><span class="iconify" data-icon="pixelarticons:book-open"></span> Open Docs</a>
    <a class="landing-btn" href="https://github.com/omarluq/termisu"><span class="iconify" data-icon="pixelarticons:github"></span> GitHub</a>
  </div>
</section>

<section class="landing-grid">
  <article class="landing-card">
    <h2><span class="iconify" data-icon="pixelarticons:dashboard"></span>Renderer</h2>
    <p>Cell buffer + diff rendering for fast screen updates with minimal terminal churn.</p>
  </article>
  <article class="landing-card">
    <h2><span class="iconify" data-icon="pixelarticons:keyboard"></span>Input</h2>
    <p>Unified key, mouse, resize, timer, and mode-change events in one loop.</p>
  </article>
  <article class="landing-card">
    <h2><span class="iconify" data-icon="pixelarticons:sliders"></span>Control</h2>
    <p>Switch modes safely with block based wrappers.</p>
  </article>
  <article class="landing-card">
    <h2><span class="iconify" data-icon="pixelarticons:server"></span>Cross-Platform</h2>
    <p>Runs cleanly on macOS, Linux, and BSD terminals.</p>
  </article>
  <article class="landing-card">
    <h2><span class="iconify" data-icon="pixelarticons:sparkles"></span>Lightweight</h2>
    <p>Small API surface focused on speed and predictable behavior.</p>
  </article>
  <article class="landing-card">
    <h2><span class="iconify" data-icon="pixelarticons:check"></span>Dependency-Free</h2>
    <p>Pure Crystal core with no runtime dependency chain to manage.</p>
  </article>
</section>

## Install In 30 Seconds

```yaml
dependencies:
  termisu:
    github: omarluq/termisu
```

```bash
shards install
```

## First Render

```crystal
require "termisu"

termisu = Termisu.new
begin
  termisu.set_cell(0, 0, 'T', fg: Termisu::Color.bright_green)
  termisu.set_cell(1, 0, 'U', fg: Termisu::Color.bright_cyan)
  termisu.set_cell(2, 0, 'I', fg: Termisu::Color.bright_blue)
  termisu.render
ensure
  termisu.close
end
```
