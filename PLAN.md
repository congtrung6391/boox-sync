# booxsync execution plan

Target: Boox **NoteX** (Android 11, firmware 4.1.1) connected to a Mac by USB-C. Transport is adb. Open source, manual install (dmg + apk). Wi-Fi out of scope, Bluetooth optional.
Companion docs: DESIGN.md (architecture), SPIKE.md (measurements). Update the Status column here as work lands.

## Facts that shape the plan (from the spike)
- adb works; enable via Apps > menu > App Management > USB Debug Mode. Link is USB 2.0, about 35 MB/s.
- No hardware H.264 encoder on the Boox. scrcpy needs `--video-codec=vp8`; scrcpy recordings buffer, so they can't be piped live.
- `adb exec-out screencap -p` works (about 1 s/frame), with a 25-byte text banner before the PNG that must be stripped.
- Pen digitizer `/dev/input/event3` streams X 0-20966, Y 0-15725, pressure 0-4095 over `adb shell getevent`.
- Toolchain on this Mac: Swift 6.3 and Command Line Tools only. **No full Xcode** (so no File Provider extension or xcodebuild archive), no Android SDK or gradle (java present). Swift Package Manager can build a SwiftUI/AppKit app and we can assemble the .app bundle and dmg by script.

## Workstreams

### WS0 Foundation (do first)
| ID | Task | Depends | Done when | Status |
|---|---|---|---|---|
| 0.1 | Phase 0 spike, adb + mirror test | | SPIKE.md written | done |
| 0.2 | Mirror script with contrast filter (`scripts/boox-mirror.sh`) | 0.1 | window works, user confirmed | done |
| 0.3 | Swift package skeleton `BooxSync` (menu bar app, SwiftUI) with build and `.app` bundle scripts | | `swift build` runs, app launches, icon in menu bar | done |
| 0.4 | `AdbService`: locate or bundle adb, device detect/hotplug, serial selection, error states (unauthorized, offline, no device) | 0.3 | UI shows connected/disconnected/needs-allow live | done |
| 0.5 | Onboarding view: shows the "enable USB Debug Mode" steps when no device | 0.4 | matches real Boox menu path | done |

### WS1 File sharing (feature 3). Lowest risk, build first
| ID | Task | Depends | Done when | Status |
|---|---|---|---|---|
| 1.1 | `BooxFS` layer: list, stat, pull, push, mkdir, rename, delete via adb (parse `ls -l`/`stat`, handle spaces and unicode in names) | 0.4 | unit tests against a fake adb plus a live test on the Boox | done |
| 1.2 | Browser window: sidebar of shortcuts (Books, Documents, Download, note), list view, breadcrumb, sort | 1.1 | can navigate `/sdcard` | done |
| 1.3 | Copy Boox to Mac: drag out to Finder, "Save to..." and multi-select | 1.2 | folder of files copies, checksums match | done |
| 1.4 | Send Mac to Boox: drop files/folders onto window, "Send to Boox" button, default Books or Documents folder | 1.2 | drop a PDF and it appears in the Boox library | done |
| 1.5 | Transfer queue with progress, cancel, error report | 1.3, 1.4 | 1 GB copy shows progress and can be cancelled | built, awaiting user test |
| 1.6 | Make pushed files visible to Boox apps (media scan broadcast, or confirm not needed) | 1.4 | file shows without reboot | best effort added (broadcast), unverified |
| 1.7 | Finder mount via local WebDAV server backed by BooxFS and `mount_webdav` (no kext, no Xcode) | 1.1 | Boox appears as a Finder volume with read and write | todo, stretch |

### WS2 Boox to Mac mirror (feature 2)
| ID | Task | Depends | Done when | Status |
|---|---|---|---|---|
| 2.1 | Port the screencap poller into the app: capture, strip banner, decode PNG, skip identical frames (hash) | 0.4 | frames arrive in app | built, awaiting user test |
| 2.2 | Mirror window with tone controls (gamma, contrast, grayscale), fit/zoom, always-on-top, orientation-aware | 2.1 | matches the quality of the script, sliders persist | built, awaiting user test |
| 2.3 | Adaptive capture rate: faster when screen changes, back off when idle | 2.1 | idle CPU near zero | built, awaiting user test |
| 2.4 | Pen reader: stream `getevent` from event3, parse ABS_X/Y/PRESSURE/BTN_TOUCH, map to screen coordinates with rotation | 0.4 | coordinates line up with a screenshot | built, awaiting user test |
| 2.5 | Live stroke overlay on the Mac, cleared when the next real frame confirms the stroke | 2.2, 2.4 | strokes appear before the e-ink refresh | built, awaiting user test |
| 2.6 | Record or screenshot the mirror (save PNG, copy to clipboard) | 2.2 | one-click snapshot | built, awaiting user test |

### WS3 Mac to Boox second display (feature 1). Highest risk
| ID | Task | Depends | Done when | Status |
|---|---|---|---|---|
| 3.0 | **Feasibility spike on the Boox**: can a sideloaded app draw full screen and trigger partial e-ink refresh via the Onyx SDK (`EpdController`) or standard Android view invalidation? Needs Android build tooling (install Android SDK/Gradle, or `aapt2`+`d8`) | | hello-world apk shows an image and we know the achievable refresh behaviour | done: plain invalidate(rect) updates look smooth on the panel |
| 3.1 | Mac virtual display via `CGVirtualDisplay` at the Boox size (1872x1404) | 0.3 | display appears in System Settings > Displays, windows can be dragged onto it | done: private CGVirtualDisplay works on macOS 26 (switches to 1872x1302 mode, parks right of main display) |
| 3.2 | Capture it with ScreenCaptureKit; grayscale; dirty-rectangle diff | 3.1 | tiles logged with sizes and rates | done: ScreenCaptureKit + gray quantise + 128 px tile diff + PNG tiles (verified: Mac desktop appeared on the Boox) |
| 3.3 | Transport: `adb reverse` plus a small framed TCP protocol (tile header, PNG/WebP payload, ack) | 0.4 | Mac sends a test tile that the apk receives | done via web: loopback HTTP + WebSocket, adb reverse, no apk |
| 3.4 | Android companion app (Kotlin): full-screen viewer, receives tiles, partial refresh, full refresh after idle to clear ghosting | 3.0, 3.3 | moving a window on the Mac shows on the Boox | superseded by the web viewer (android/display apk kept as an unused fallback) |
| 3.5 | Refresh policy tuning: A2/fast mode while changing, quality mode when idle, max update rate | 3.4 | text readable, ghosting acceptable | todo |
| 3.6 | Install apk from the Mac app (`adb install`, version check, launch with `am start`) | 3.4, 0.4 | one click installs and starts | not needed: the browser is opened with am start, no install |
| 3.7 | Touch/pen input from Boox back to Mac cursor (optional) | 3.4, 2.4 | tap moves the Mac cursor | todo, optional |
| 3.9 | **Alternative with no app install:** Mac app serves a web page on localhost, `adb reverse` tunnels it over USB, the Boox's own browser (org.chromium.chrome) opens it via `am start -a VIEW`; `input tap` triggers fullscreen. Tiles over WebSocket drawn on a canvas. Verified that the page loads and animates via adb reverse; fullscreen, refresh quality and WebSocket tiles untested | 0.3 | decision between APK and web viewer | chosen and built: web viewer |
| 3.10 | **Window picker for the second display:** list windows in the Display tab, send one to the Boox display (fills the display below its menu bar) with one click, pull it back to its old place; pull everything back on Stop. Needs Accessibility permission. Mac pointer drawn into the capture is a switch (default on) | 3.1, 3.2 | pick a window, it appears on the Boox; pull back restores it | built (incl. bring to top), awaiting user test |
| 3.12 | **Component variants:** each component has 3-4 styles chosen in the inspector (clock: digital, time only, analog, 12-hour; date: big day, one line, week and day; calendar: month, week strip, two weeks; weather: current and forecast, current only, forecast only, compact; to-do: checklist, compact, focus; now playing: artwork and text, artwork only, text only; CPU, memory, disk: bar, ring, big number; network: rates, rates and graph, compact; battery: bars, rings, compact; note: normal, large, quote). Older saved layouts load as the first style | 3.11 | variant picker works, every variant renders | built, all variants rendered and checked, awaiting user test |
| 3.11 | **Dashboard tab (layout editor) and components:** 12x8 grid editor with drag, resize, palette, presets (Desk, Calm, Focus, Music, Monitor, Clock only), outlines switch. Components: clock, date, month calendar, weather (Open-Meteo, 5-day forecast, city search, units), to-do (local list or Apple Reminders), now playing (Spotify or Music), CPU, memory, disk, network, battery (Mac and Boox), note. Shown as a wallpaper-style window on the Boox display, behind any windows sent there. Display tab reduced to start/stop, pointer, dashboard switch and windows | 3.10 | dashboard editable and visible on the Boox | built, layouts verified by render, awaiting user test |
| 3.8 | Fallback if 3.0 fails: use the Mac to push a still-image view via an existing viewer app opened with `am start`, or abandon feature 1 | 3.0 | decision recorded | contingency |

### WS4 Packaging and release
| ID | Task | Depends | Done when | Status |
|---|---|---|---|---|
| 4.1 | Bundle `adb` binary and licence notices into the .app | 0.3 | app works on a Mac without Homebrew | done |
| 4.2 | Build script: `.app`, ad-hoc codesign, `.dmg` | 0.3 | dmg opens and drag-installs | done |
| 4.3 | Android build: Gradle project, signed debug/release apk | 3.4 | apk installs by hand | todo |
| 4.4 | README: install (right-click Open, `xattr`), enabling USB Debug Mode, troubleshooting | 4.2 | a new user can follow it | done (update as features land) |
| 4.5 | GitHub Actions: build dmg and apk on tag, attach to release | 4.2, 4.3 | tag produces a release | todo |
| 4.7 | Stable local code signing (`scripts/setup-signing.sh`, build script signs with it): permissions survive rebuilds | 4.2 | designated requirement identical across builds | done |
| 4.6 | Licence file (Apache-2.0 or MIT) and third-party notices | | present in repo and bundle | done: MIT, THIRD_PARTY_NOTICES.md |

### WS5 Quality and polish (ongoing)
| ID | Task | Done when | Status |
|---|---|---|---|
| 5.1 | Unit tests: adb output parsers, protocol framing, coordinate mapping | `swift run CoreChecks` green (XCTest unavailable without full Xcode; parser checks exist) | partial |
| 5.2 | Robustness: unplug/replug, adb daemon restart, device asleep, multiple devices | app recovers without restart | todo |
| 5.3 | Settings: default folders, tone preset, launch at login | persisted | todo |
| 5.4 | Bluetooth (nice to have): evaluate for notifications or pairing only | decision recorded | todo, optional |

## Suggested order
1. WS0 (0.3 to 0.5), the app shell and adb layer.
2. WS1 core (1.1 to 1.5), the first complete feature, usable daily.
3. WS2 (2.1 to 2.3, then 2.6), then 2.4/2.5 if wanted.
4. **WS3 gate 3.0 early**: run the feasibility spike right after WS0 in parallel with WS1, because its result decides whether feature 1 is worth doing. Then 3.1 to 3.6.
5. WS4 packaging after each milestone ships; WS5 throughout.

## Milestones
- M1: app shell + file browser with drag and drop (WS0 + 1.1 to 1.5).
- M2: mirror window with filter and idle backoff (2.1 to 2.3, 2.6).
- M3: feature 1 feasibility answered (3.0), design updated.
- M4: second display working end to end (3.1 to 3.6).
- M5: first public release: dmg, apk, README, CI (WS4).

## Risks
| Risk | Impact | Mitigation |
|---|---|---|
| Sideloaded app can't control e-ink refresh well | Feature 1 looks bad | gate 3.0; accept slow full-screen refresh, or drop feature 1 |
| `CGVirtualDisplay` is a private API and may change in future macOS | Feature 1 breaks | isolate it behind one class; test on current macOS 26.4 |
| No full Xcode installed | No File Provider extension, no xcodebuild archive | use SwiftPM plus scripted bundling; WebDAV instead of File Provider |
| No Android SDK here | Can't build the apk yet | install SDK command-line tools in step 3.0 (needs user approval for downloads) |
| Boox firmware updates change the debug menu or screencap output | Setup or capture breaks | keep banner strip tolerant; document firmware tested (4.1.1) |
| Screenshot polling is about 1 fps and uses USB bandwidth | Mirror feels laggy | adaptive rate (2.3), pen overlay (2.5) |

## Open questions for the user
- App name and bundle id (working name: BooxSync).
- Licence: Apache-2.0 or MIT?
- Default Boox folder for "Send to Boox" (Books vs Documents vs Push)?
- OK to install the Android SDK command-line tools (about 1 GB) when we reach 3.0?
