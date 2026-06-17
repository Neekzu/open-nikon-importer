#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/Build"
PLIST_TEMPLATE="$ROOT_DIR/Packaging/Info.plist"
APP_NAME="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleName' "$PLIST_TEMPLATE")"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST_TEMPLATE")"
ASSET_NAME="${APP_NAME// /.}"

"$ROOT_DIR/Scripts/package-dmg.sh"

CHECKSUMS="$BUILD_DIR/checksums-$VERSION.txt"
rm -f "$CHECKSUMS"
(
    cd "$BUILD_DIR"
    shasum -a 256 "$ASSET_NAME-$VERSION-macos.zip" "$ASSET_NAME-$VERSION-macos.dmg" > "$(basename "$CHECKSUMS")"
)

printf 'Release files:\n'
printf '  %s\n' "$BUILD_DIR/$ASSET_NAME-$VERSION-macos.zip"
printf '  %s\n' "$BUILD_DIR/$ASSET_NAME-$VERSION-macos.dmg"
printf '  %s\n' "$CHECKSUMS"
