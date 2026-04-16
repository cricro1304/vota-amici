#!/usr/bin/env bash
# Vercel build script: installs Flutter stable, builds Flutter web under /play/,
# then assembles the final dist/ with landing page + static assets at root
# and Flutter web output at /play/.
set -euo pipefail

echo "==> Installing Flutter (stable)..."
if [ ! -d "_flutter" ]; then
  git clone --depth 1 -b stable https://github.com/flutter/flutter.git _flutter
fi
export PATH="$PWD/_flutter/bin:$PATH"
flutter config --no-analytics >/dev/null 2>&1 || true
flutter --version
flutter doctor -v || true

echo "==> Writing flutter_app/.env from Vercel env vars..."
# Map existing Vercel env vars (reused from the old Vite app) into the
# variable names the Flutter app expects via flutter_dotenv.
: "${VITE_SUPABASE_URL:?VITE_SUPABASE_URL is required}"
: "${VITE_SUPABASE_PUBLISHABLE_KEY:?VITE_SUPABASE_PUBLISHABLE_KEY is required}"
APP_URL_VALUE="${APP_URL:-https://ilpiu.org}"
cat > flutter_app/.env <<EOF
SUPABASE_URL=${VITE_SUPABASE_URL}
SUPABASE_ANON_KEY=${VITE_SUPABASE_PUBLISHABLE_KEY}
APP_URL=${APP_URL_VALUE}
EOF

# Preview / dev-branch Vercel deploys get the bot+auto-start toggle enabled
# so we can QA a full game alone. Production stays clean — the toggle is
# gated behind `kEnableDevMode` in the Flutter code (core/constants.dart).
# VERCEL_ENV is set by Vercel to one of: production | preview | development.
DEV_MODE_DEFINE=""
if [ "${VERCEL_ENV:-}" != "production" ]; then
  DEV_MODE_DEFINE="--dart-define=ENABLE_DEV_MODE=true"
  echo "==> Non-production deploy (VERCEL_ENV=${VERCEL_ENV:-unset}) — enabling dev/bot toggle"
fi

echo "==> Building Flutter web (release, base-href=/play/)..."
pushd flutter_app >/dev/null
# Ensure the web platform is registered (idempotent; preserves existing web/ files)
flutter create . --platforms web --project-name vota_amici >/dev/null
flutter pub get
flutter build web --release --base-href /play/ $DEV_MODE_DEFINE
popd >/dev/null

echo "==> Assembling dist/..."
rm -rf dist
mkdir -p dist/play

# Root landing + packs + shared static assets
cp landing-page.html dist/
cp packs.html dist/
# public/ holds assets/, favicon, robots, etc. -> root
if [ -d public ]; then
  cp -R public/. dist/
fi

# Flutter web build output -> /play/
cp -R flutter_app/build/web/. dist/play/

echo "==> Minifying landing CSS/JS with esbuild..."
# esbuild is zero-config and already fast on Vercel's build image.
# We minify only the landing-page assets (not Flutter's own bundle).
# Fails soft: if esbuild is missing we skip rather than break the deploy.
if command -v npx >/dev/null 2>&1; then
  for f in dist/assets/css/landing.css dist/assets/css/shared.css dist/assets/css/packs.css; do
    if [ -f "$f" ]; then
      npx --yes esbuild "$f" --minify --loader=css --log-level=error \
        --outfile="$f.min" && mv "$f.min" "$f"
    fi
  done
  for f in dist/assets/js/landing.js dist/assets/js/landing.translations.js \
           dist/assets/js/packs.js dist/assets/js/packs.translations.js \
           dist/assets/js/i18n.js; do
    if [ -f "$f" ]; then
      npx --yes esbuild "$f" --minify --log-level=error \
        --outfile="$f.min" && mv "$f.min" "$f"
    fi
  done
else
  echo "   (npx not available — skipping minification)"
fi

echo "==> Done. Contents:"
ls -la dist
ls -la dist/play | head -10
