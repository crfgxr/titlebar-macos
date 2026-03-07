#!/usr/bin/env bash
set -euo pipefail

APP_NAME="TitleBar"
ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$ROOT_DIR/build"
DERIVED_DATA="$BUILD_DIR/DerivedData"
APP_SRC="$DERIVED_DATA/Build/Products/Release/$APP_NAME.app"
APP_DEST="/Applications/$APP_NAME.app"

echo "Building $APP_NAME..."
xcodebuild \
  -project "$ROOT_DIR/$APP_NAME.xcodeproj" \
  -scheme "$APP_NAME" \
  -configuration Release \
  -derivedDataPath "$DERIVED_DATA" \
  build \
  CONFIGURATION_BUILD_DIR="$DERIVED_DATA/Build/Products/Release" \
  2>&1 | tail -5

if [ ! -d "$APP_SRC" ]; then
  echo "Error: Build failed — $APP_SRC not found"
  exit 1
fi

# Kill running instance if any
if pgrep -x "$APP_NAME" > /dev/null 2>&1; then
  echo "Stopping running $APP_NAME..."
  killall "$APP_NAME" 2>/dev/null || true
  sleep 1
fi

echo "Installing to $APP_DEST..."
rm -rf "$APP_DEST"
cp -R "$APP_SRC" "$APP_DEST"

# Reset Accessibility permission (ad-hoc signing changes hash each build)
BUNDLE_ID=$(/usr/libexec/PlistBuddy -c "Print CFBundleIdentifier" "$APP_DEST/Contents/Info.plist")
echo "Resetting Accessibility permission for $BUNDLE_ID..."
tccutil reset Accessibility "$BUNDLE_ID" 2>/dev/null || true

echo "Launching $APP_NAME..."
open "$APP_DEST"

echo "Done."
