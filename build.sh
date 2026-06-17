#!/usr/bin/env bash
# Build "FreeRDP Launcher.app" from the AppleScript source and install it.
# Usage: ./build.sh [DEST_DIR]   (default: /Applications)
set -euo pipefail

APP_NAME="FreeRDP Launcher"
HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="$HERE/src/$APP_NAME.applescript"
DEST="${1:-/Applications}"
OUT="$DEST/$APP_NAME.app"

if [[ ! -f "$SRC" ]]; then
  echo "error: source not found: $SRC" >&2
  exit 1
fi

rm -rf "$OUT"
osacompile -o "$OUT" "$SRC"
echo "Installed: $OUT"
echo "Launch it from Spotlight / Launchpad, or: open \"$OUT\""
