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

detach_dmg_devices() {
    hdiutil info | awk -v image_path="$DMG_PATH" '
        /^image-path[[:space:]]*:/ {
            in_target = index($0, image_path) > 0
            next
        }
        /^================================================/ {
            in_target = 0
            next
        }
        in_target && /^\/dev\/disk[0-9]/ {
            print $1
        }
    ' | sort -r | while read -r device; do
        hdiutil detach "$device" >/dev/null 2>&1 || true
    done
}

wait_for_dmg_release() {
    for _ in $(seq 1 20); do
        detach_dmg_devices
        if ! hdiutil info | grep -Fq "$DMG_PATH"; then
            return 0
        fi
        sleep 0.25
    done
}

"$ROOT_DIR/Scripts/package-app.sh"

rm -rf "$DMG_ROOT"
mkdir -p "$DMG_ROOT"
cp -R "$APP_BUNDLE" "$DMG_ROOT/$APP_NAME.app"
ln -s /Applications "$DMG_ROOT/Applications"
cp "$ROOT_DIR/docs/INSTALL-DMG.txt" "$DMG_ROOT/READ ME FIRST.txt"

detach_dmg_devices
rm -f "$DMG_PATH"
hdiutil create \
    -volname "$VOLUME_NAME" \
    -srcfolder "$DMG_ROOT" \
    -ov \
    -format UDZO \
    "$DMG_PATH"

wait_for_dmg_release
hdiutil verify "$DMG_PATH"
printf 'DMG: %s\n' "$DMG_PATH"
