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

echo "==> Building Flutter web (release, base-href=/play/)..."
pushd flutter_app >/dev/null
# Ensure the web platform is registered (idempotent; preserves existing web/ files)
flutter create . --platforms web --project-name vota_amici >/dev/null
flutter pub get
flutter build web --release --base-href /play/
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

echo "==> Done. Contents:"
ls -la dist
ls -la dist/play | head -10
