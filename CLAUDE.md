# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository layout

| Directory | Contents |
|-----------|----------|
| `mac/` | macOS SwiftUI app (primary platform) — see `mac/CLAUDE.md` |
| `website/` | Astro static site (marketing / landing page) |
| `windows/` | Windows port (placeholder) |

## Website (`website/`)

Astro project. All commands run from `website/`:

```bash
npm install       # install deps
npm run dev       # dev server at localhost:4321
npm run build     # production build → dist/
npm run preview   # preview production build
```

## Mac app

See [`mac/CLAUDE.md`](mac/CLAUDE.md) for build instructions, full architecture, and design decisions.
