#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/Build"
PLIST_TEMPLATE="$ROOT_DIR/Packaging/Info.plist"
APP_NAME="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleName' "$PLIST_TEMPLATE")"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST_TEMPLATE")"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
DMG_ROOT="$BUILD_DIR/dmg-root"
DMG_PATH="$BUILD_DIR/$APP_NAME-$VERSION-macos.dmg"
VOLUME_NAME="$APP_NAME $VERSION"

"$ROOT_DIR/Scripts/package-app.sh"

rm -rf "$DMG_ROOT"
mkdir -p "$DMG_ROOT"
cp -R "$APP_BUNDLE" "$DMG_ROOT/$APP_NAME.app"
ln -s /Applications "$DMG_ROOT/Applications"
cp "$ROOT_DIR/docs/INSTALL-DMG.txt" "$DMG_ROOT/READ ME FIRST.txt"

rm -f "$DMG_PATH"
hdiutil create \
    -volname "$VOLUME_NAME" \
    -srcfolder "$DMG_ROOT" \
    -ov \
    -format UDZO \
    "$DMG_PATH"

hdiutil verify "$DMG_PATH"
printf 'DMG: %s\n' "$DMG_PATH"
