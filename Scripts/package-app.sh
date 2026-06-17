#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT_DIR/App"
BUILD_DIR="$ROOT_DIR/Build"
PLIST_TEMPLATE="$ROOT_DIR/Packaging/Info.plist"
ICON_FILE="$ROOT_DIR/Packaging/AppIcon.icns"
EXECUTABLE="ZRImporter"

APP_NAME="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleName' "$PLIST_TEMPLATE")"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST_TEMPLATE")"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
ARCHIVE_PATH="$BUILD_DIR/$APP_NAME-$VERSION-macos.zip"

swift build --package-path "$APP_DIR" -c release --product "$EXECUTABLE"
BIN_DIR="$(swift build --package-path "$APP_DIR" -c release --show-bin-path)"
BIN_PATH="$BIN_DIR/$EXECUTABLE"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"
cp "$BIN_PATH" "$APP_BUNDLE/Contents/MacOS/$EXECUTABLE"
cp "$PLIST_TEMPLATE" "$APP_BUNDLE/Contents/Info.plist"
cp "$ICON_FILE" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
chmod +x "$APP_BUNDLE/Contents/MacOS/$EXECUTABLE"

plutil -lint "$APP_BUNDLE/Contents/Info.plist"
codesign --force --deep --sign "${CODE_SIGN_IDENTITY:--}" "$APP_BUNDLE"
codesign --verify --deep --strict "$APP_BUNDLE"

rm -f "$ARCHIVE_PATH"
ditto -c -k --keepParent "$APP_BUNDLE" "$ARCHIVE_PATH"

printf 'Built: %s\n' "$APP_BUNDLE"
printf 'Archive: %s\n' "$ARCHIVE_PATH"
