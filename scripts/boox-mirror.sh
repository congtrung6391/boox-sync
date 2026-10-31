#!/bin/bash
# Mirror the Boox screen to a window on the Mac over USB (adb + ffplay).
# Polls `adb exec-out screencap` (about 1 frame per second, plenty for e-ink) and
# shows the frames in ffplay with a contrast/gamma filter, because the e-ink
# capture looks washed out. (scrcpy was dropped: the NoteX only has a software VP8
# encoder and scrcpy recordings buffer until the stream closes, so they can't be
# piped into a filter.)
#
# Usage: scripts/boox-mirror.sh [--gamma G] [--contrast C] [--raw]
#   --gamma    below 1 darkens mid-greys (default 0.45)
#   --contrast above 1 increases contrast (default 1.8)
#   --raw      plain scrcpy window, no filter
set -euo pipefail

GAMMA=0.45
CONTRAST=1.8
RAW=0
while [ $# -gt 0 ]; do
  case "$1" in
    --gamma) GAMMA=$2; shift 2 ;;
    --contrast) CONTRAST=$2; shift 2 ;;
    --raw) RAW=1; shift ;;
    *) echo "unknown option: $1" >&2; exit 1 ;;
  esac
done

command -v adb >/dev/null || { echo "adb not found: brew install android-platform-tools" >&2; exit 1; }
if ! adb devices | grep -qw device; then
  echo "No adb device. On the Boox: Apps > menu > App Management > USB Debug Mode, then replug and tap Allow." >&2
  exit 1
fi

if [ "$RAW" = 1 ]; then
  command -v scrcpy >/dev/null || { echo "scrcpy not found: brew install scrcpy" >&2; exit 1; }
  exec scrcpy --video-codec=vp8 --max-fps=5 --max-size=1872 --video-bit-rate=4M \
    --no-audio --no-control --window-title="Boox"
fi

command -v ffplay >/dev/null || { echo "ffplay not found: brew install ffmpeg" >&2; exit 1; }

# The Boox screencap prints a 25-byte text banner ("capture from screenshot!\n") before the PNG.
capture() {
  while true; do
    adb exec-out screencap -p | tail -c +26 || exit 0
  done
}

capture | ffplay -loglevel error -fflags nobuffer -flags low_delay -window_title "Boox" \
  -f image2pipe -framerate 2 \
  -vf "eq=contrast=$CONTRAST:gamma=$GAMMA" -i -
