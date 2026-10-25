#!/bin/bash
# Packages build/ROG Gaming Center.app into a drag-to-install disk image:
#   build/ROG-Gaming-Center-<version>.dmg
#
# Usage: ./make-dmg.sh            (builds the app first if it's missing)
#        ./make-dmg.sh --rebuild  (always runs build.sh first)
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="ROG Gaming Center"
BUILD_DIR="./build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"

if [ "${1:-}" == "--rebuild" ] || [ ! -d "$APP_BUNDLE" ]; then
    ./build.sh
fi

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP_BUNDLE/Contents/Info.plist")
DMG_PATH="$BUILD_DIR/ROG-Gaming-Center-$VERSION.dmg"
STAGING=$(mktemp -d "${TMPDIR:-/tmp}/rog-dmg.XXXXXX")
RW_DMG="$STAGING.rw.dmg"
trap 'rm -rf "$STAGING" "$RW_DMG"' EXIT

echo "-> Staging $APP_NAME $VERSION..."
cp -R "$APP_BUNDLE" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

# Volume icon: the app icon, shown on the desktop and in the Finder sidebar.
if [ -f "./Resources/AppIcon.icns" ]; then
    cp "./Resources/AppIcon.icns" "$STAGING/.VolumeIcon.icns"
fi

echo "-> Creating disk image..."
hdiutil create -quiet -srcfolder "$STAGING" -volname "$APP_NAME" -fs HFS+ -format UDRW -ov "$RW_DMG"

# Mark the volume as having a custom icon (needs a writable image).
if [ -f "$STAGING/.VolumeIcon.icns" ] && command -v SetFile >/dev/null; then
    MOUNT_DIR=$(hdiutil attach -nobrowse -noverify -noautoopen "$RW_DMG" | awk -F '\t' '/\/Volumes\// {print $NF}')
    SetFile -a C "$MOUNT_DIR"
    hdiutil detach -quiet "$MOUNT_DIR"
fi

rm -f "$DMG_PATH"
hdiutil convert -quiet "$RW_DMG" -format UDZO -imagekey zlib-level=9 -o "$DMG_PATH"

# Sign the image with the same identity build.sh would use, when a real one exists.
IDENTITY="${SIGNING_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null | grep "Apple Development" | head -1 | awk -F '"' '{print $2}' || true)}"
if [ -n "$IDENTITY" ] && [ "$IDENTITY" != "-" ]; then
    codesign --force --sign "$IDENTITY" "$DMG_PATH"
    echo "-> Signed disk image with: $IDENTITY"
fi

hdiutil verify -quiet "$DMG_PATH"
echo "✓ Created $DMG_PATH ($(du -h "$DMG_PATH" | cut -f1))"
