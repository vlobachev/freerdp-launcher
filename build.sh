#!/usr/bin/env bash
# Build "FreeRDP Launcher.app" from the SwiftPM target and assemble a .app bundle.
# Usage: ./build.sh [DEST_DIR]
#   ./build.sh                # -> ./dist/FreeRDP Launcher.app
#   ./build.sh /Applications  # also installs a copy there
set -euo pipefail

APP_NAME="FreeRDP Launcher"
BIN_NAME="FreeRDPLauncher"
HERE="$(cd "$(dirname "$0")" && pwd)"
APP="$HERE/dist/$APP_NAME.app"

echo "==> swift build -c release"
swift build -c release --package-path "$HERE"
BIN="$(swift build -c release --package-path "$HERE" --show-bin-path)/$BIN_NAME"

echo "==> assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$APP_NAME"
cp "$HERE/Resources/Info.plist" "$APP/Contents/Info.plist"
[ -f "$HERE/Resources/AppIcon.icns" ] && cp "$HERE/Resources/AppIcon.icns" "$APP/Contents/Resources/"

echo "==> ad-hoc codesign"
codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true

echo "Built: $APP"

if [ "${1:-}" != "" ]; then
  DEST="$1/$APP_NAME.app"
  rm -rf "$DEST"
  cp -R "$APP" "$1/"
  echo "Installed: $DEST"
fi

echo "Run: open \"$APP\""
