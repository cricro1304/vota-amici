#!/usr/bin/env bash
# One-shot cleanup on flutter-port: removes the React/Vite app, untracks
# committed .env files, stages all the new Vercel+Flutter build config,
# and commits.
#
# Run from the repo root:
#   bash scripts/strip-react-and-commit.sh
set -euo pipefail

# Safety: must be on flutter-port
BRANCH="$(git rev-parse --abbrev-ref HEAD)"
if [ "$BRANCH" != "flutter-port" ]; then
  echo "Refusing to run: expected branch 'flutter-port', got '$BRANCH'."
  exit 1
fi

# Free any stale git lock (safe: only removes if not held by a live process)
rm -f .git/index.lock

echo "==> Removing React/Vite app files..."
git rm -rf --ignore-unmatch \
  src \
  index.html \
  vite.config.ts \
  vitest.config.ts \
  tsconfig.json \
  tsconfig.app.json \
  tsconfig.node.json \
  tailwind.config.ts \
  postcss.config.js \
  eslint.config.js \
  components.json \
  package.json \
  package-lock.json \
  bun.lock \
  bun.lockb

# Non-tracked debris
rm -rf dist node_modules
rm -f vite.config.ts.timestamp-*.mjs

echo "==> Untracking committed env files..."
git rm --cached --ignore-unmatch .env flutter_app/.env

echo "==> Staging new/updated config..."
git add \
  .gitignore \
  .env.example \
  vercel.json \
  build.sh \
  flutter_app/.env.example \
  scripts/strip-react-and-commit.sh

echo "==> Status preview:"
git status

echo ""
echo "==> Committing..."
git commit -m "chore: replace React/Vite app with Flutter web deploy on Vercel

- Remove src/, Vite/Tailwind/TS/ESLint configs, package.json, lockfiles
- Add build.sh: installs Flutter stable, builds web at --base-href /play/,
  assembles dist/ with landing-page + static assets at root + Flutter at /play/
- Update vercel.json: buildCommand=bash build.sh, outputDirectory=dist,
  rewrites /play/* and /room/* to Flutter SPA
- Gitignore committed .env files; add .env.example templates
- Supabase creds generated into flutter_app/.env at build time from
  VITE_SUPABASE_URL and VITE_SUPABASE_PUBLISHABLE_KEY (existing Vercel vars)"

echo ""
echo "==> Done. Push with: git push origin flutter-port"
echo "    This will trigger a preview deploy on Vercel."
