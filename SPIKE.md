# Phase 0 spike results (2026-10-31)

Device: Boox **NoteX**, Android 11 (SDK 30), arm64-v8a, firmware 4.1.1 (2026-02-11). Mac: macOS 26.4, adb 1.0.41, scrcpy 5.0.1 (Homebrew).

## Enabling adb
Not under Android Developer options. On this firmware it is **Apps > top-right menu > App Management > USB Debug Mode**. After enabling, the USB product ID changes from 0x4EE1 (MTP only) to 0x4EE2 and `adb devices` lists the device after a replug and "Allow" prompt.

## Display
- `wm size`: 1404x1872 (portrait natural), density 240.
- Screenshot while in landscape: 1872x1404. The Boox rotates, so the app must read the current orientation.

## File transfer over adb (USB 2.0 link, high speed)
- push 50 MB: 35.1 MB/s. pull 50 MB: 36.6 MB/s. Checksums match.
- Storage: `/sdcard` is `/data/media`, 23 GB, 11 GB used. Folders include Books, Documents, Download, note, noteTemplate, Push.
- Verdict: adb is fast enough. Feature 3 is feasible with adb alone.

## Screen capture
- `adb exec-out screencap -p` works (~0.9 s per frame) but Boox's screencap prints a 25-byte text banner, `capture from screenshot!\n`, before the PNG. It must be stripped (`tail -c +26`) or the PNG is invalid. Fine for e-ink rates.
- **scrcpy fails with its default H.264 encoder.** The device has no usable hardware encoders, only software VP8 and VP9 (`c2.android.vp8.encoder`, `c2.android.vp9.encoder`).
- **scrcpy works with VP8**: `scrcpy --video-codec=vp8 --max-size=1280 --max-fps=5` recorded 8 s of video without errors (1280x960).

## Pen input
- `/dev/input/event3` is `onyx_emp_Wacom I2C Digitizer`; touch is `/dev/input/event4` (`cyttsp5_mt`). The shell user can list them. Reading live pen events while drawing has not been tested yet.

## Still to test
1. Does the live pen stroke show up in scrcpy/screencap while you draw in the Note app, or only after a refresh? (needs you drawing)
2. Does `adb shell getevent -l /dev/input/event3` stream pen coordinates and pressure while drawing?
3. Whether sideloaded apps can use the Onyx SDK for partial refresh (needed for the second display).

## Design impact
- Feature 3: go ahead with adb push/pull/ls.
- Feature 2: use `--video-codec=vp8` with a low fps, or periodic screencap with banner stripping. Decide after the pen test.
- Feature 1: still needs a companion app. No hardware video encoder means we should send still tiles (PNG/WebP), not video.

## Live drawing test (done, user drawing in the Boox Note app)
- **Screencap shows strokes.** Screenshots taken 4 s apart while drawing in the Note app (notebook "sdpractice") contained the new strokes, so the pen layer is in the captured frame. Highlighter colours come out black (mono panel in capture).
- **scrcpy VP8** recorded 141 frames in 20 s at `--max-fps=5` (~7 fps measured, 1280x960 output). No errors.
- **Pen events stream.** `adb shell getevent -lt /dev/input/event3` produced ~17k lines in 20 s, with ABS_X, ABS_Y, pressure and BTN_TOUCH / BTN_TOOL_BRUSH down/up events.
- Digitizer axes: X 0-20966, Y 0-15725, pressure (0x18) 0-4095, distance (0x19) 0-255, tilt X/Y (0x1a/0x1b) -63..63. Sample rate roughly 400 Hz (about 2.6 ms between reports).
- Note: X/Y axes are the digitizer's native orientation; they must be rotated to match the screen orientation (landscape 1872x1404) when drawing on the Mac.

## Verdict
- Feature 2 works without any companion app. Preferred path: scrcpy VP8 at low fps for the picture. Optional: overlay live pen strokes from getevent for lower latency than the e-ink refresh.
- Remaining unknown: Onyx SDK partial refresh from a sideloaded app (feature 1).

## Phase 3.0: second-display feasibility (sideloaded app on the Boox)
Toolchain installed with Homebrew: openjdk@17, android-commandlinetools, `platforms;android-30`, `build-tools;30.0.3` (SDK root `/opt/homebrew/share/android-commandlinetools`). `android/probe/build.sh` builds an apk with aapt2 + javac + d8 + apksigner, no Gradle (16 KB).

- A sideloaded app installs with `adb install` and draws on the panel. Window size was 1872x1303: the Boox keeps a ~100 px navigation bar even with immersive flags set.
- **Boox "App Freeze" disables newly installed apps** (`pm list packages -d` showed the probe as disabled and `am start` failed with "Activity class does not exist"). Workaround: `adb shell pm enable <package>` before launching, and turn off App Freeze for the app in Apps > App Management > App Freeze. The Mac app must run `pm enable` before each launch.
- Without the Onyx SDK, `com.onyx.android.sdk.api.device.epd.EpdController` is not present. The hidden framework class `android.onyx.ViewUpdateHelper` is loadable by reflection from a normal app, which is what the SDK builds on. Its methods were not listed yet (reflection printed nothing).
- Build fingerprint is `userdebug`, so `adb root` may be available (not tried).
- Open: how plain `invalidate(rect)` partial updates look on the e-ink panel (ghosting, flicker, update speed). Needs a visual check by the user; the probe app shows a moving square, a clock, and a grey ramp.

### 3.0 result and 3.3/3.4 first cut
- User check: partial updates from a plain sideloaded app look smooth, no flicker. The gate passes, so feature 1 is feasible without the Onyx SDK.
- `android/display` (BooxDisplay.apk, 16 KB) listens on 127.0.0.1:7788 and draws tiles. Needs `android.permission.INTERNET` or the socket fails with EPERM.
- Protocol: device sends `BXH1` + u16 width + u16 height; Mac sends `'T' x y w h length payload`, payload raw DEFLATE of gray bytes. Mac compresses with Foundation `.zlib`, which is raw DEFLATE and inflates with `java.util.zip.Inflater(nowrap=true)`.
- `swift run CoreChecks --display-test` pushes a gradient frame and a moving square. The Boox view reports 1872x1303; a full 1872x1303 frame was sent in a few ms (a mostly white frame compresses to almost nothing).
- Freeze race: `pm enable` immediately after install can be undone by the Boox freeze service, so the Mac side retries `pm enable` + `am start` and checks the output for "Error".

## Web viewer test (no app install): Boox browser over `adb reverse`
Page served from the Mac on localhost:8765, `adb reverse tcp:8765 tcp:8765`, opened with `am start -a android.intent.action.VIEW -d http://localhost:8765/`. Browser is the Boox build of Chromium (`org.chromium.chrome`).

- **Resolution:** with the browser toolbars hidden the viewport is 856x573 CSS px at devicePixelRatio 2.1875, i.e. a **1873x1253 px canvas**, the same area as the app (status bar ~50 px on top and the 100 px navigation bar remain). With toolbars showing the viewport is only 856x477 CSS px.
- **Fullscreen:** `requestFullscreen()` from a page script never resolves its promise on this browser, but a tap on the page (injected with `adb shell input tap 900 700`, which counts as a user gesture) does hide the toolbars. The fullscreen state persisted for the tab across later `am start` loads. Not yet checked from a cold browser start.
- **Fidelity at native size:** a canvas sized innerWidth x devicePixelRatio renders 1:1: 1 px lines, 2 px lines, 16 grey steps and 10-24 px text are all crisp in a screenshot.
- **Throughput (full 1873x1253 frame, median of 8):** PNG fetch + `createImageBitmap` + draw 80 ms; raw gray (with or without gzip) fetch 93 ms; raw to canvas with a JS gray-to-RGBA loop 93 ms. Over 12 full frames per second, far beyond what the panel can show.
- **Partial updates:** 300x300 tiles drawn at 10 Hz achieved 9.8 per second; a requestAnimationFrame loop moving a small square ran at 39 fps. So the browser is not the bottleneck; the e-ink panel is.
- Not tested: WebSocket streaming from the Mac (Network.framework supports it), cold-start fullscreen reliability, what the panel looks like for fast updates (needs eyes), the Boox auto-refreshing or sleeping the browser in the background.
- Test server: `android/web-bench-server.py` (needs an `index.html` next to it, kept in the scratchpad).

## Second display built on the web viewer (verified)
- `swift run CoreChecks --session-test 40` runs the whole chain: loopback server, `adb reverse`, Boox Chromium opened fresh (`am force-stop` first so old tabs cannot steal the WebSocket), `input tap` for fullscreen (works from a cold browser start), virtual display, ScreenCaptureKit, tile diff, WebSocket. A screenshot of the Boox during the run showed the Mac's virtual display (menu bar and wallpaper) in grayscale at full width.
- Virtual display: `CGVirtualDisplay` via KVC and `objc_msgSend`. macOS starts it in a 1024x712 mode, so the app switches to the requested 1872x1302 mode and puts it to the right of the main display.
- Gotchas found: `NWListener.requiredInterfaceType = .loopback` still listens on all interfaces, so listeners bind `requiredLocalEndpoint` 127.0.0.1; HTTP strings need real `\r\n`; only the newest browser tab may hold the WebSocket, so background tabs stop reconnecting; CoreChecks stdout is block-buffered when redirected, so wait on the process, not on log lines.
- Cost: the first full frame is about 350-770 KB of PNG (16 gray levels), later updates are a few KB to ~250 KB.
- Chrome shows a "No connection / See downloads" toast over the bottom of the page on this device. Not yet explained or removed.
