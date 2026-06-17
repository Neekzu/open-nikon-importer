#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
"$ROOT_DIR/Scripts/package-app.sh"

APP_NAME="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleName' "$ROOT_DIR/Packaging/Info.plist")"
SOURCE_APP="$ROOT_DIR/Build/$APP_NAME.app"
TARGET_DIR="${LOCAL_INSTALL_DIR:-/Applications}"
TARGET_APP="$TARGET_DIR/$APP_NAME.app"

mkdir -p "$TARGET_DIR"
osascript -e 'tell application "Open Nikon Importer" to quit' >/dev/null 2>&1 || true
osascript -e 'tell application "ZR Importer" to quit' >/dev/null 2>&1 || true
rm -rf "$TARGET_APP"
rm -rf "$HOME/Applications/ZR Importer.app" "/Applications/ZR Importer.app"
cp -R "$SOURCE_APP" "$TARGET_APP"
printf 'Installed: %s\n' "$TARGET_APP"
