# booxsync design

Goal: use a Boox Note Air as (1) a secondary Mac display, (2) a mirror that shows what you draw on the Boox on the Mac, and (3) a Finder-like file browser from Mac into the Boox. Wi-Fi is out of scope.

## Transport
USB-C cable (Thunderbolt port on the Mac side, USB 2.0 link in practice) plus **adb**.
- `adb forward` / `adb reverse` tunnel TCP over USB, so the Mac app and the Boox app talk over plain sockets with no network.
- adb also gives file access (`push`/`pull`/`ls`) and shell access without any app on the Boox.
- Bluetooth is a later nice-to-have (pairing/notifications only; too slow for display).
- Requires: Developer options > USB debugging on the Boox, and a bundled `adb` binary in the Mac app.

## Components
1. **Mac app (Swift, SwiftUI, menu bar).** Owns adb, the virtual display, capture/encode, the file browser and the mirror window.
2. **Boox companion app (Kotlin, sideloaded with `adb install`).** Full-screen viewer for feature 1. Uses the Onyx SDK (`EpdController`) to set refresh mode and do partial refreshes.

## Feature 1: Mac to Boox secondary display
- Create a virtual display on the Mac at the Boox resolution (target device is a Boox Note X, 13.3"; expected around 2200x1650, to be confirmed with `adb shell wm size`). Uses `CGVirtualDisplay` (private API, same approach as DeskPad and BetterDisplay).
- Capture it with ScreenCaptureKit, convert to grayscale, and compute dirty rectangles against the previous frame.
- Send changed tiles only, compressed (PNG/WebP for text, or HEVC), at 1-3 fps max, over the adb tunnel.
- Companion app blits tiles into a SurfaceView and requests a partial EPD refresh of the dirty region (A2/fast mode while changing, full refresh after idle to clear ghosting).
- Input back from Boox (touch/pen as mouse) is optional, later.

## Feature 2: Boox to Mac mirror
- Phase 1: spawn **scrcpy** (or embed its server jar, Apache-2.0) over adb and show it in a window. No Boox app needed.
- Risk: the Boox Note app draws live pen strokes on a fast overlay that may not appear in the normal framebuffer, so a screen capture can lag or miss live strokes until a refresh.
- Fallback: read the pen digitizer directly with `adb shell getevent` (EMR/Wacom device) and draw strokes live on the Mac, optionally over a periodic screenshot as the background.

## Feature 3: file sharing (Mac pulls from and pushes to the Boox)
Built on adb only, nothing needed on the Boox.
- Step 1: browser window in the Mac app with drag and drop (`adb ls/pull/push`).
- Step 2: real Finder integration. Options: a File Provider extension (robust, shows in the Finder sidebar), or a local WebDAV server backed by adb that Finder mounts with `mount_webdav` (cheap, quirkier). macFUSE is avoided because it needs a system extension.
- USB 2.0 caps throughput at roughly 30-40 MB/s in practice.

## Phases
0. Spike: install adb and scrcpy, confirm `adb devices` sees the Boox, measure `adb push` speed, test scrcpy against the Note app while drawing.
1. File browser (feature 3, step 1). Quickest to value, lowest risk.
2. Mirror window (feature 2, scrcpy).
3. Companion app plus secondary display (feature 1). Highest effort.
4. Finder integration, live-stroke fallback, Bluetooth.

## Distribution
Open source, manual install, no stores.
- Mac: prebuilt `.dmg` on GitHub Releases. No Developer ID or notarization, so users right-click > Open the first time (or `xattr -dr com.apple.quarantine`). Private APIs are fine for this.
- Boox: prebuilt `.apk`, installed by the Mac app itself with `adb install` (or by hand). No Play Store.
- The dmg bundles `adb` and the scrcpy server jar (both Apache-2.0, so bundling is allowed; keep their licence notices). Suggested project licence: Apache-2.0 or MIT.
- A GitHub Actions workflow builds the dmg and apk on tag and attaches them to the release.

## Open questions
- Exact Boox model and Android version.
- Does the Boox's Android allow USB debugging and a sideloaded app (expected yes)?
- Is a virtual display acceptable (private API, not App Store distributable)? Assumed yes for a personal tool.
