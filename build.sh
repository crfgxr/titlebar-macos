#!/usr/bin/env bash
set -euo pipefail

APP_NAME="TitleBar"
ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$ROOT_DIR/build"
APP_DIR="$BUILD_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
ICON_SRC="$ROOT_DIR/assets/TitleBar.png"
ICONSET_DIR="$BUILD_DIR/TitleBar.iconset"

mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

swiftc -O \
  -framework AppKit \
  -framework ApplicationServices \
  "$ROOT_DIR/Sources/main.swift" \
  -o "$MACOS_DIR/$APP_NAME"

cp "$ROOT_DIR/Info.plist" "$CONTENTS_DIR/Info.plist"

if [ -f "$ICON_SRC" ]; then
  rm -rf "$ICONSET_DIR"
  mkdir -p "$ICONSET_DIR"
  sips -z 16 16 "$ICON_SRC" --out "$ICONSET_DIR/icon_16x16.png" > /dev/null
  sips -z 32 32 "$ICON_SRC" --out "$ICONSET_DIR/icon_16x16@2x.png" > /dev/null
  sips -z 32 32 "$ICON_SRC" --out "$ICONSET_DIR/icon_32x32.png" > /dev/null
  sips -z 64 64 "$ICON_SRC" --out "$ICONSET_DIR/icon_32x32@2x.png" > /dev/null
  sips -z 128 128 "$ICON_SRC" --out "$ICONSET_DIR/icon_128x128.png" > /dev/null
  sips -z 256 256 "$ICON_SRC" --out "$ICONSET_DIR/icon_128x128@2x.png" > /dev/null
  sips -z 256 256 "$ICON_SRC" --out "$ICONSET_DIR/icon_256x256.png" > /dev/null
  sips -z 512 512 "$ICON_SRC" --out "$ICONSET_DIR/icon_256x256@2x.png" > /dev/null
  sips -z 512 512 "$ICON_SRC" --out "$ICONSET_DIR/icon_512x512.png" > /dev/null
  sips -z 1024 1024 "$ICON_SRC" --out "$ICONSET_DIR/icon_512x512@2x.png" > /dev/null
  iconutil -c icns "$ICONSET_DIR" -o "$RESOURCES_DIR/TitleBar.icns"
fi

echo "Built $APP_DIR"
