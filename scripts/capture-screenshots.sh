#!/bin/bash
# Regenerates the README screenshots in assets/screenshots/ from the app's demo mode (fake data only).
# Needs Screen Recording permission for the terminal running it. Only the demo window is captured, never the screen.
# Usage: scripts/capture-screenshots.sh
set -euo pipefail
cd "$(dirname "$0")/.."

scripts/build-app.sh >/dev/null
APP=dist/BooxSync.app/Contents/MacOS/BooxSync
OUT=assets/screenshots
mkdir -p "$OUT"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# Prints the id of the largest normal window of a process.
cat > "$WORK/window-id.swift" <<'SWIFT'
import CoreGraphics
import Foundation
let pid = Int32(CommandLine.arguments[1])!
let windows = (CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]]) ?? []
var best: (id: Int, area: CGFloat) = (0, 0)
for window in windows where (window[kCGWindowOwnerPID as String] as? Int32) == pid && (window[kCGWindowLayer as String] as? Int) == 0 {
    guard let bounds = window[kCGWindowBounds as String] as? [String: CGFloat] else { continue }
    let area = (bounds["Width"] ?? 0) * (bounds["Height"] ?? 0)
    if area > best.area { best = (window[kCGWindowNumber as String] as? Int ?? 0, area) }
}
print(best.id)
SWIFT

shot() {   # name, demo tab, extra args...
  local name=$1 tab=$2; shift 2
  # A unique marker identifies this demo run, so a BooxSync you have open yourself is never captured or closed.
  local token="shot-$name-$$-$RANDOM"
  # Launched through `open` so the app is frontmost and the window is active (not grayed out).
  open -n dist/BooxSync.app --args --demo "$tab" --demo-run "$token" "$@" -AppleLanguages "(en)" -AppleLocale en_US
  local pid=""
  for _ in $(seq 1 40); do
    sleep 0.5
    pid=$(pgrep -f -- "--demo-run $token" | head -1 || true)
    [ -n "$pid" ] && break
  done
  [ -z "$pid" ] && { echo "the demo app did not start for $name" >&2; return 1; }
  local id=0
  for _ in $(seq 1 40); do
    sleep 0.5
    id=$(swift "$WORK/window-id.swift" "$pid" 2>/dev/null || echo 0)
    [ "$id" != "0" ] && break
  done
  [ "$id" = "0" ] && { echo "no window for $name" >&2; kill "$pid" 2>/dev/null || true; return 1; }
  sleep 3   # let the demo content settle
  screencapture -l "$id" -o -x "$OUT/$name.png"
  kill "$pid" 2>/dev/null || true
  while kill -0 "$pid" 2>/dev/null; do sleep 0.3; done
  sips -Z 1700 "$OUT/$name.png" >/dev/null
  echo "wrote $OUT/$name.png"
}

shot files files --demo-path /sdcard/Books
shot display display
# mirror.png and dashboard.png are real captures of the app (they show a live Boox), taken by hand.

# What the Boox shows: the dashboard rendered with sample data (no window or permission needed).
"$APP" --render-dashboard "$OUT/boox-dashboard-light.png" 0 -AppleLanguages "(en)" -AppleLocale en_US >/dev/null
"$APP" --render-dashboard "$OUT/boox-dashboard-dark.png" 0 dark -AppleLanguages "(en)" -AppleLocale en_US >/dev/null
"$APP" --render-dashboard "$OUT/boox-dashboard-monitor.png" 4 -AppleLanguages "(en)" -AppleLocale en_US >/dev/null
echo "wrote the dashboard renders"
ls -l "$OUT" | awk 'NR>1 {printf "%8d  %s\n", $5, $9}'
