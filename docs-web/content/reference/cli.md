+++
title = "Tooling"
description = "Common local commands for Termisu development."
weight = 10
+++

# Tooling

In this repository, we use `bin/hace` wrappers for common workflows.
The task runner is [hace](https://github.com/ralsina/hace).

## Validation

```bash
bin/hace spec
bin/hace ameba
```

## Formatting

```bash
bin/hace format
bin/hace format:check
```

## Full Local Pass

```bash
bin/hace
```

## Docs Site (Hwaro)

```bash
bin/hace docs:build
bin/hace docs:serve
```

If `hwaro` is missing, install from <https://hwaro.hahwul.com/> first.
Local docs tasks default `DOCS_BASE_URL` to `http://localhost:3000`; override with:

```bash
DOCS_BASE_URL=https://termisu.io bin/hace docs:build
```

## Deploy (Netlify via Hwaro)

```bash
export NETLIFY_AUTH_TOKEN=...
export NETLIFY_SITE_ID=...
cd docs-web
hwaro deploy netlify --dry-run
hwaro deploy netlify
```

Preview deploy (non-production):

```bash
cd docs-web
hwaro deploy netlify-preview
```

## Netlify Build Notes

Netlify CI uses the repo-level `netlify.toml` config with `base = "docs-web"` and `publish = "public"`.
The build command downloads a prebuilt `hwaro` Linux binary, so Crystal/shards are not required in Netlify.
`base_url` is dynamic in CI and resolved as:
`DOCS_BASE_URL` (explicit override) -> `DEPLOY_PRIME_URL` -> `URL` -> `https://termisu.io`.
You can override the pinned hwaro version with `HWARO_VERSION` in Netlify environment variables.
