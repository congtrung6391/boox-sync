#!/bin/bash
# Build dist/BooxSync.app from the Swift package (no Xcode needed).
# Bundles adb (universal, system libraries only) so the app works without Homebrew.
# Usage: scripts/build-app.sh [--adb /path/to/adb] [--no-bundle-adb]
set -euo pipefail
cd "$(dirname "$0")/.."

ADB_SRC=$(command -v adb || true)
while [ $# -gt 0 ]; do
  case "$1" in
    --adb) ADB_SRC=$2; shift 2 ;;
    --no-bundle-adb) ADB_SRC=""; shift ;;
    *) echo "unknown option: $1" >&2; exit 1 ;;
  esac
done

# Prefer the stable local certificate (scripts/setup-signing.sh) so macOS permissions survive rebuilds.
SIGN_ID=$(security find-identity -p codesigning | awk '/BooxSync Local Signing/ {print $2; exit}')
if [ -z "$SIGN_ID" ]; then
  SIGN_ID="-"
  echo "No local signing certificate: using an ad-hoc signature (permissions reset on every build). Run scripts/setup-signing.sh."
fi

swift build -c release
BIN=$(swift build -c release --show-bin-path)/BooxSync

APP=dist/BooxSync.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/BooxSync"
if [ -n "$ADB_SRC" ]; then
  ADB_REAL=$(python3 -c 'import os,sys;print(os.path.realpath(sys.argv[1]))' "$ADB_SRC")
  cp "$ADB_REAL" "$APP/Contents/Resources/adb"
  mkdir -p "$APP/Contents/Resources/licenses"
  NOTICE="$(dirname "$ADB_REAL")/NOTICE.txt"
  [ -f "$NOTICE" ] && cp "$NOTICE" "$APP/Contents/Resources/licenses/android-platform-tools-NOTICE.txt"
  codesign --force --sign "$SIGN_ID" "$APP/Contents/Resources/adb"
  echo "Bundled adb: $("$APP/Contents/Resources/adb" version | head -1)"
else
  echo "adb not bundled; the app will look for adb on this Mac"
fi

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>BooxSync</string>
  <key>CFBundleDisplayName</key><string>BooxSync</string>
  <key>CFBundleIdentifier</key><string>dev.booxsync.app</string>
  <key>CFBundleExecutable</key><string>BooxSync</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSAppleEventsUsageDescription</key><string>BooxSync reads the current track from Spotify or Music to show it on the Boox dashboard.</string>
</dict>
</plist>
PLIST

codesign --force --sign "$SIGN_ID" "$APP"
echo "Built $APP"
