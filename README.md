# BooxSync

A Mac app for a Boox NoteX connected by USB-C (adb underneath, no Wi-Fi):

- **Files:** browse the Boox, copy files to the Mac and send files to it, with drag and drop.
- **Mirror:** see the Boox screen on the Mac, with live pen strokes while you draw (landscape).
- **Display:** use the Boox as a second Mac display over USB (virtual display, the Boox browser as the viewer, nothing installed on the Boox). Needs Screen Recording permission.

Tested on a Boox NoteX, firmware 4.1.1, macOS 26.

## Install
1. Download `BooxSync-<version>.dmg`, open it, drag BooxSync to Applications.
2. The app is not notarized. The first time, right-click it and choose **Open**, or run:
   ```bash
   xattr -dr com.apple.quarantine /Applications/BooxSync.app
   ```
3. adb is bundled; nothing else to install.

## Connect the Boox
1. On the Boox open **Apps**, the menu at the top right, **App Management**, and switch on **USB Debug Mode**.
2. Plug the Boox into the Mac with a data-capable USB-C cable.
3. Tap **Allow** on the "Allow USB debugging?" prompt on the Boox (tick "Always allow").

BooxSync shows these steps itself whenever the Boox is not ready.

## Build from source
Needs Swift 6 (Command Line Tools are enough, no Xcode).
```bash
scripts/build-app.sh      # dist/BooxSync.app, bundles adb if found (brew install android-platform-tools)
scripts/make-dmg.sh       # dist/BooxSync-<version>.dmg
swift run CoreChecks      # parser and protocol checks; add --live with a Boox connected
```

## Other tools
`scripts/boox-mirror.sh` is the original command-line mirror (needs `brew install ffmpeg`).

## Notes
- The USB link is USB 2.0: about 35 MB/s for files, about 3 frames per second for the mirror.
- Bundled adb is Google's Android platform-tools (Apache-2.0); its notice is inside the app.

Docs: DESIGN.md, PLAN.md, SPIKE.md.
