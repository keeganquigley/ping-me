# docs/ — Ping Me user guide site

This folder is a tiny, fully static site that renders the Ping Me user guide.
It is designed to deploy to [Vercel](https://vercel.com) with no build step.

## Contents

- `index.html` — the pre-rendered user guide page. Self-contained: inline CSS,
  no JavaScript, no external assets, light/dark mode via `prefers-color-scheme`.
- `USER_GUIDE.md` — the Markdown source of the guide, exposed at
  `/USER_GUIDE.md` so the "Download Markdown" link on the page works.
- `vercel.json` — minimal Vercel config (clean URLs, sensible security
  headers). No build step, no framework.

## Deploy to Vercel

The fastest path:

1. Go to [vercel.com/new](https://vercel.com/new) and import this repository.
2. In the project settings, set **Root Directory** to `docs`.
3. Framework Preset: **Other**. Build & Output Settings: leave all commands
   blank (there is nothing to build).
4. Click **Deploy**. Vercel will serve `index.html` at the project URL.

Alternatively, with the Vercel CLI:

```bash
cd docs
npx vercel        # first deploy (follow prompts)
npx vercel --prod # promote to production
```

Pushes to the default branch trigger a new deploy automatically once the
project is linked.

## Preview locally

Because the page is self-contained static HTML, any static server works:

```bash
cd docs
python3 -m http.server 8000
# open http://localhost:8000
```

Or just double-click `index.html` to open it from the filesystem.
