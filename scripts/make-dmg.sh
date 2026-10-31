#!/bin/bash
# Build dist/BooxSync-<version>.dmg containing BooxSync.app and an Applications shortcut.
# Usage: scripts/make-dmg.sh [build-app.sh options]
set -euo pipefail
cd "$(dirname "$0")/.."

scripts/build-app.sh "$@"

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" dist/BooxSync.app/Contents/Info.plist)
DMG="dist/BooxSync-$VERSION.dmg"
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT

cp -R dist/BooxSync.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
hdiutil create -volname "BooxSync" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
echo "Built $DMG ($(du -h "$DMG" | cut -f1))"
