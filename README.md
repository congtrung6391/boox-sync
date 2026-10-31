<p align="center"><img src="assets/logo.png" width="128" alt="BooxSync logo"></p>

# BooxSync

A Mac app for a Boox NoteX connected by USB-C (adb underneath, no Wi-Fi):

- **Files:** browse the Boox, copy files to the Mac and send files to it, with drag and drop.
- **Mirror:** see the Boox screen on the Mac, with live pen strokes while you draw (landscape).
- **Display:** use the Boox as a second Mac display over USB (virtual display, the Boox browser as the viewer, nothing installed on the Boox). Pick which windows go on it, or leave a dashboard there. The Dashboard tab is a layout editor with components such as clock, calendar, weather, to-do (local or Reminders), now playing, system stats and notes; each has several styles (analog or digital clock, ring or bar gauges, and so on). Needs Screen Recording and Accessibility permission; Automation for Spotify/Music and Reminders access are optional. Weather uses Open-Meteo and needs internet on the Mac.

Tested on a Boox NoteX, firmware 4.1.1, macOS 26.

## Install
Get `BooxSync-<version>.dmg` from one of these (see [Releases](#releases)):

- **GitHub Releases:** https://github.com/congtrung6391/boox-sync/releases
- **GitHub package registry (ghcr.io):**
  ```bash
  brew install oras
  oras pull ghcr.io/congtrung6391/boox-sync:latest      # or a version, e.g. :0.2.0
  ```
  If the package is private, log in first with a personal access token that has `read:packages`:
  `echo "$TOKEN" | oras login ghcr.io -u <github-user> --password-stdin`.

Then:

1. Open the dmg and drag BooxSync to Applications.
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
scripts/make-dmg.sh       # dist/BooxSync-<version>.dmg (BOOXSYNC_VERSION and BOOXSYNC_BUILD set the version)
swift run CoreChecks      # parser and protocol checks; add --live with a Boox connected
swift scripts/make-icon.swift   # regenerates Resources/AppIcon.icns and assets/logo.png
```

## Releases
Releases are built by a manually triggered GitHub Actions workflow, `.github/workflows/release.yml`:

1. Open **Actions > Release build > Run workflow** on GitHub.
2. Enter the version (for example `0.2.0`) and choose:
   - **prerelease**: mark the release as a pre-release (the package is then not tagged `latest`),
   - **publish_package**: push the dmg to the GitHub package registry as `ghcr.io/congtrung6391/boox-sync:<version>`,
   - **create_release**: also create a GitHub Release `v<version>` with the dmg and a `.sha256` file.
3. The workflow runs the checks, bundles adb, builds `dist/BooxSync-<version>.dmg` on a macOS runner, and publishes it.
   The dmg is also kept as a run artifact.

What the workflow does not do:

- **Notarization.** Without an Apple Developer account the app is not notarized, so macOS shows the unidentified-developer warning (right-click > Open, or `xattr -dr com.apple.quarantine /Applications/BooxSync.app`).
- **Signing.** By default the app is ad-hoc signed, and macOS asks for the permissions again after each update. To keep permissions across releases, sign with the same certificate every time: export your `BooxSync Local Signing` certificate from Keychain Access as a `.p12` and add these repository secrets: `MACOS_CERT_P12_BASE64` (`base64 -i cert.p12`), `MACOS_CERT_PASSWORD`, and `MACOS_CERT_NAME` (`BooxSync Local Signing`).
- **The Android apps.** `android/` holds an optional fallback and a probe, which the release does not build.

Locally, `BOOXSYNC_VERSION=0.2.0 scripts/make-dmg.sh` produces the same dmg. The package registry holds the dmg as an OCI artifact, so use `oras` (above) to download it; the Release page is the easier route for most people.

## Keeping permissions across rebuilds (developers)
macOS ties Screen Recording, Accessibility and Automation grants to the app's code signature, and an ad-hoc signature changes on every build. Run this once to create a local self-signed certificate in your login keychain; `scripts/build-app.sh` then signs with it automatically:
```bash
scripts/setup-signing.sh
```
After the first signed build you grant the permissions once; later rebuilds keep them. Remove the certificate with `security delete-identity -c "BooxSync Local Signing"`.

## Other tools
`scripts/boox-mirror.sh` is the original command-line mirror (needs `brew install ffmpeg`).

## Notes
- The USB link is USB 2.0: about 35 MB/s for files, about 3 frames per second for the mirror.
- Bundled adb is Google's Android platform-tools (Apache-2.0); its notice is inside the app.
- Weather data by [Open-Meteo.com](https://open-meteo.com/) (CC BY 4.0).

## Licence
MIT, see [LICENSE](LICENSE). Third-party notices, including the bundled adb and the Open-Meteo weather data attribution, are in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

Docs: DESIGN.md, PLAN.md, SPIKE.md.
