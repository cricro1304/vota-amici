#!/usr/bin/env bash
# scripts/setup_ios.sh — one-shot iOS setup for the vota_amici Flutter app.
#
# Idempotent: safe to re-run after a git clean or after regenerating the
# platform folder. Run from anywhere; the script cds into flutter_app/.
#
# Prereqs (on macOS):
#   * Xcode 14+ installed from the App Store and opened at least once
#     (xcodebuild -runFirstLaunch will have run).
#   * CocoaPods installed:   sudo gem install cocoapods
#   * Flutter SDK on PATH:   flutter --version  should print a version.
#
# What it does, in order:
#   1. Runs `flutter create --platforms=ios` if ios/ is missing. This does
#      NOT overwrite lib/ or pubspec.yaml — it only adds platform files.
#   2. Patches the iOS bundle id → org.ilpiu.app (all three build configs).
#   3. Sets CFBundleDisplayName → "Chi è il più?" in Info.plist.
#   4. Registers the votaamici:// URL scheme so invite links can deep-link
#      into the app (e.g. votaamici://room/ABCDE).
#   5. Runs `pod install` in ios/ and `flutter pub get` at the root.
#   6. Ensures .env exists (copies from .env.example if not).
#
# After this completes, open ios/Runner.xcworkspace in Xcode, pick your
# personal team under Signing & Capabilities, select a simulator (or a
# connected iPhone with developer mode on), and press ⌘R.

set -euo pipefail

# Resolve the flutter_app directory relative to this script so the caller
# can run it from anywhere, including symlinked locations.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$APP_DIR"

BUNDLE_ID="org.ilpiu.app"
DISPLAY_NAME="Chi è il più?"
URL_SCHEME="votaamici"

# -----------------------------------------------------------------------------
# Pre-flight checks — fail fast with actionable messages instead of cryptic
# errors halfway through.
# -----------------------------------------------------------------------------
if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "✗ iOS setup requires macOS. Current OS: $(uname -s)"
  exit 1
fi

if ! command -v flutter >/dev/null 2>&1; then
  echo "✗ flutter not found on PATH."
  echo "   Install from https://docs.flutter.dev/get-started/install/macos"
  exit 1
fi

if ! command -v pod >/dev/null 2>&1; then
  echo "✗ CocoaPods (pod) not found on PATH."
  echo "   Install with: sudo gem install cocoapods"
  exit 1
fi

if ! command -v /usr/libexec/PlistBuddy >/dev/null 2>&1; then
  echo "✗ /usr/libexec/PlistBuddy not found — is this macOS?"
  exit 1
fi

# -----------------------------------------------------------------------------
# 1. Generate ios/ if missing.
#    `flutter create .` on an existing project restores platform folders
#    and Gradle/CocoaPods config WITHOUT touching lib/ or pubspec.yaml.
# -----------------------------------------------------------------------------
if [[ ! -d "ios" ]]; then
  echo "→ Generating ios/ platform folder (flutter create)..."
  flutter create . --platforms=ios --project-name vota_amici >/dev/null
else
  echo "✓ ios/ already exists — skipping scaffold."
fi

PLIST="ios/Runner/Info.plist"
PBXPROJ="ios/Runner.xcodeproj/project.pbxproj"

if [[ ! -f "$PLIST" || ! -f "$PBXPROJ" ]]; then
  echo "✗ Expected Xcode project files not found. Did flutter create fail?"
  exit 1
fi

# -----------------------------------------------------------------------------
# 2. Bundle id — sed over project.pbxproj. The default flutter-create output
#    uses com.example.votaAmici (camelcase derived from `vota_amici`). We
#    rewrite all three occurrences (Debug, Release, Profile).
# -----------------------------------------------------------------------------
echo "→ Setting bundle id → $BUNDLE_ID"

# BSD sed (macOS) needs `-i ''` for in-place. Match any com.example.* id so
# the script still works if the default ever changes across Flutter versions.
sed -i '' -E \
  "s|PRODUCT_BUNDLE_IDENTIFIER = com\\.example\\.[A-Za-z0-9_]+;|PRODUCT_BUNDLE_IDENTIFIER = $BUNDLE_ID;|g" \
  "$PBXPROJ"

# Verify — if the sed missed (e.g. someone already hand-edited the id), warn.
if ! grep -q "PRODUCT_BUNDLE_IDENTIFIER = $BUNDLE_ID;" "$PBXPROJ"; then
  echo "⚠  Did not find PRODUCT_BUNDLE_IDENTIFIER = $BUNDLE_ID; in the"
  echo "    project file. Current values:"
  grep PRODUCT_BUNDLE_IDENTIFIER "$PBXPROJ" | sort -u | sed 's/^/    /'
  echo "    Set it manually in Xcode → Runner target → Signing & Capabilities."
fi

# -----------------------------------------------------------------------------
# 3. Display name — "Chi è il più?" under the app icon on the home screen.
# -----------------------------------------------------------------------------
echo "→ Setting display name → $DISPLAY_NAME"

# `Set` fails if the key doesn't exist yet; fall back to `Add`.
if ! /usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName $DISPLAY_NAME" "$PLIST" 2>/dev/null; then
  /usr/libexec/PlistBuddy -c "Add :CFBundleDisplayName string $DISPLAY_NAME" "$PLIST"
fi

# -----------------------------------------------------------------------------
# 4. URL scheme — votaamici://room/ABCDE deep links. We reset the array on
#    every run so re-running the script doesn't accumulate duplicates.
# -----------------------------------------------------------------------------
echo "→ Registering URL scheme → $URL_SCHEME://"

/usr/libexec/PlistBuddy -c "Delete :CFBundleURLTypes" "$PLIST" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :CFBundleURLTypes array" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :CFBundleURLTypes:0 dict" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :CFBundleURLTypes:0:CFBundleURLName string $BUNDLE_ID" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :CFBundleURLTypes:0:CFBundleURLSchemes array" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :CFBundleURLTypes:0:CFBundleURLSchemes:0 string $URL_SCHEME" "$PLIST"

# -----------------------------------------------------------------------------
# 5. CocoaPods + Flutter deps.
#
# Order matters here:
#   a. `flutter pub get` first — the Podfile references plugin pods that are
#      only linked after pub resolves the plugin registry.
#   b. `flutter precache --ios` second — CocoaPods' post-install hook calls
#      `podhelper.rb`, which requires
#          $FLUTTER_ROOT/bin/cache/artifacts/engine/ios/Flutter.xcframework
#      On a machine that's only ever built web or android, that artifact
#      isn't downloaded yet and `pod install` fails with:
#         "…/Flutter.xcframework must exist. If you're running pod install
#          manually, make sure 'flutter precache --ios' is executed first"
#      Precaching is idempotent — a no-op if the artifact is already there.
#   c. `pod install` last — now that both pub deps and the engine xcframework
#      are in place, CocoaPods can resolve and generate the Xcode project.
# -----------------------------------------------------------------------------
echo "→ flutter pub get"
flutter pub get >/dev/null

echo "→ flutter precache --ios (downloads Flutter.xcframework if missing)"
flutter precache --ios >/dev/null

echo "→ pod install (this takes a minute the first time)..."
( cd ios && pod install )

# -----------------------------------------------------------------------------
# 6. .env — supabase URL + anon key. The app won't start without it.
# -----------------------------------------------------------------------------
if [[ ! -f ".env" ]]; then
  if [[ -f ".env.example" ]]; then
    cp .env.example .env
    echo "⚠  Created .env from .env.example. EDIT it with your Supabase URL"
    echo "    and anon key before running the app, or it will crash at boot."
  else
    echo "⚠  No .env and no .env.example — you'll need to create .env by hand."
  fi
else
  echo "✓ .env already present."
fi

# -----------------------------------------------------------------------------
# Done.
# -----------------------------------------------------------------------------
cat <<EOF

✅  iOS setup complete.

Next steps:
   1. open ios/Runner.xcworkspace
   2. In Xcode, select the Runner target → Signing & Capabilities →
      Team: pick your personal Apple ID (free tier is fine).
   3. Pick an iOS Simulator in the scheme selector (or plug in an iPhone).
   4. ⌘R — or from the terminal: flutter run -d ios

Deep-link test once installed:
   xcrun simctl openurl booted votaamici://room/ABCDE

EOF
