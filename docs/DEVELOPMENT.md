# BooxSync development guide

This is for people who build, change or release BooxSync. If you only want to use the app, see the [README](../README.md).

## What is in the repository

| Path | What it is |
|---|---|
| `Sources/BooxSync` | The SwiftUI app: Files, Mirror, Display and Dashboard tabs, the menu bar item, and the dashboard window |
| `Sources/BooxSyncCore` | Everything that is not UI: adb access (`BooxFS`), screen capture, pen input, the second-display pipeline (`SecondDisplaySession`, `DisplayServer`, `TileDiffer`), window moving, weather, reminders, now playing, system stats, and the dashboard layout engine |
| `Sources/CVirtualDisplay` | A small Objective-C shim around the private `CGVirtualDisplay` classes |
| `Sources/CoreChecks` | A plain assertion runner (see Checks below) |
| `scripts/` | Build, dmg, icon, signing, release and git hook scripts |
| `.github/workflows/release.yml` | The manual release workflow |
| `Resources/`, `assets/` | The generated app icons and the README logo |
| `android/` | An optional Android fallback viewer and a probe app (the shipped second display needs no app on the Boox) |
| `docs/` | `DESIGN.md` (architecture and plan), `PLAN.md` (task list), `SPIKE.md` (measurements from the Boox), `INVESTIGATION.md` (early research) |
| `VERSION`, `CHANGELOG.md` | Current version and history, both maintained by the release workflow |

### How it works, in short

- **Transport.** Everything goes over USB through `adb`. A copy of adb is bundled in the app and found first by `AdbLocator`; otherwise Homebrew or `PATH` is used.
- **Files.** `BooxFS` runs `adb shell`, `push` and `pull`, with a transfer queue in the app.
- **Mirror.** The app polls `adb exec-out 'screencap | gzip -1'` (about 0.33 s per frame), keeps only changed frames, and overlays live pen strokes read from the Wacom digitizer with `adb shell getevent`.
- **Second display.** `SecondDisplaySession` creates a virtual display, captures it with ScreenCaptureKit, quantizes it to 16 grays, diffs 128 px tiles and sends the changed ones as PNG over a WebSocket. The server listens on 127.0.0.1 only (ports 8765 for the page and 8766 for the socket); `adb reverse` makes them reachable from the Boox, and the Boox's own Chromium shows the page. Display tabs are closed through Chrome's DevTools socket.
- **Dashboard.** A 12x8 grid layout (`DashboardLayout`) of components with several variants each, rendered as a borderless window just above the desktop on the virtual display.

`docs/DESIGN.md` and `docs/SPIKE.md` have the reasoning and measurements behind these choices.

## Requirements

- macOS 14 or later, Swift 6 (the Command Line Tools are enough; full Xcode is not needed).
- For bundling adb: `brew install --cask android-platform-tools`.
- A Boox with USB debugging on, for the live checks (see the README for how to enable it).
- Python 3 for the release tooling.

## Build and run

```bash
scripts/build-app.sh             # builds dist/BooxSync.app (dev channel), bundles adb if found
open dist/BooxSync.app

scripts/make-dmg.sh              # dist/BooxSync-<version>.dmg
swift scripts/make-icon.swift    # regenerates Resources/AppIcon.icns, Resources/AppIcon-dev.icns, assets/logo.png
```

Useful environment variables for `build-app.sh`: `BOOXSYNC_CHANNEL` (`dev` or `release`), `BOOXSYNC_VERSION`, `BOOXSYNC_BUILD`, `BOOXSYNC_SIGN_IDENTITY`. Without a version it uses the `VERSION` file.

`scripts/boox-mirror.sh` is the original command-line mirror (needs `brew install ffmpeg`).

## Checks and tests

XCTest and Swift Testing are not part of the Command Line Tools, so the Swift checks are an executable:

```bash
swift run CoreChecks                    # offline checks: parsers, layout engine, weather parsing, system stats, ...
swift run CoreChecks --live             # also needs a Boox connected: file push/pull, screen capture, pen stream
swift run CoreChecks --session-test 40  # the whole second display for 40 s (needs the Boox and Screen Recording)
swift run CoreChecks --web-test         # server and page only, with a test pattern
swift run CoreChecks --vd-test          # create and destroy the virtual display
swift run CoreChecks --weather-test     # live Open-Meteo request
python3 scripts/test_release.py         # unit tests for the release script
```

Output is block-buffered when redirected to a file, so wait for the process to end instead of watching the log.

### Demo mode and README screenshots

`BooxSync --demo files|mirror|display|dashboard` runs the real app with made-up data: a fake Boox, sample files, windows, music, weather and to-dos. Nothing is read from the Boox or the Mac, nothing is saved, and no adb, network or permission prompt is involved (add `--demo-path /sdcard/Books` to open the Files tab in a folder). `scripts/capture-screenshots.sh` uses it to regenerate everything in `assets/screenshots/`: it makes the Files and Display shots (the two that would list real files and windows): it launches the dev app once per tab in English, captures only that window with `screencapture -l`, and renders the Boox dashboards headlessly. It needs Screen Recording permission for your terminal, and identifies its own windows by a unique `--demo-run` marker so a BooxSync you have open is left alone. `mirror.png` is a real capture: open the release app on that tab and run `screencapture -l <windowID> -o -x`. Re-run after UI changes and commit the images.

Layouts can be checked without a window or any permission:

```bash
BooxSync --render-dashboard out.png [presetIndex] [dark] [appkit]   # draw the dashboard with sample data
BooxSync --render-variants clock out.png                            # every style of one component
```

(Run it from the build output, for example `.build/debug/BooxSync`.)

## Dev builds and release builds

Local builds and the released app are separate apps to macOS, so their permissions never mix:

| | Release (from the dmg) | Dev (`scripts/build-app.sh`) |
|---|---|---|
| Name in the Dock and Privacy lists | BooxSync | BooxSync Dev (icon with an amber DEV badge) |
| Bundle id | `dev.booxsync.app` | `dev.booxsync.app.dev` |
| Channel | `BOOXSYNC_CHANNEL=release` (the release workflow) | the default |

Saved settings (such as the dashboard layout) live per bundle id. Both use the same Boox display ports, so run one at a time.

### Code signing and permissions

macOS ties Screen Recording, Accessibility and Automation grants to the bundle id and the code signature. An ad-hoc signature changes on every build, which makes the grants go stale. Create a local self-signed certificate once and every build is signed with it:

```bash
scripts/setup-signing.sh
```

After the first signed build you grant the permissions once; later rebuilds keep them. Remove the certificate with `security delete-identity -c "BooxSync Local Signing"`.

If permissions still do not stick, or you see duplicate rows in Privacy settings, reset one identity and grant it again:

```bash
tccutil reset ScreenCapture dev.booxsync.app.dev     # dev build; use dev.booxsync.app for the release
tccutil reset Accessibility dev.booxsync.app.dev
tccutil reset AppleEvents dev.booxsync.app.dev
```

A reset removes the grant, so do not repeat it after granting.

**Release installed next to a local build.** Releases built before the dev/release split (1.0.x and 1.1.0) used the bundle id `dev.booxsync.app` for local builds too, so a downloaded release and an older local build left mixed or duplicate rows in Privacy settings. Clear the release identity once and grant it again; end users never need this:

```bash
tccutil reset ScreenCapture dev.booxsync.app
tccutil reset Accessibility dev.booxsync.app
tccutil reset AppleEvents dev.booxsync.app
```

## Commit messages, versions and the changelog

Versions follow [Semantic Versioning](https://semver.org/) and are chosen from commit messages written as [Conventional Commits](https://www.conventionalcommits.org/): `type(scope): subject`, first line at most 100 characters.

| Commit | Version bump |
|---|---|
| `feat: ...` | minor (1.0.0 to 1.1.0) |
| `fix: ...`, `perf: ...`, `revert: ...` | patch (1.0.0 to 1.0.1) |
| `feat!: ...`, or `BREAKING CHANGE:` in the body | major (while below 1.0.0, a minor bump instead) |
| `docs`, `refactor` | listed in the changelog, no bump on their own |
| `build`, `ci`, `chore`, `test`, `style` | not listed, no bump |

- Enable the `commit-msg` hook once per clone with `scripts/install-hooks.sh`. It rejects anything that is not a Conventional Commit.
- `VERSION` and `CHANGELOG.md` are written by the release workflow. Do not edit them by hand.
- Preview the next release at any time: `python3 scripts/release.py plan` (nothing is written without `--write`).
- Force a bump or an exact version with `--bump patch|minor|major` or `--version 1.2.0`. With nothing releasable since the last tag (only docs or chores) the script stops and asks for a forced bump.
- Old commits that are not Conventional Commits are only listed under "Other changes" and never cause a bump.

## Releases

Releases are built by a manually triggered GitHub Actions workflow, `.github/workflows/release.yml`:

1. Open **Actions > Release build > Run workflow** on GitHub, on the `main` branch.
2. Choose:
   - **bump**: `auto` (from the commit messages since the last tag), or force `patch`, `minor` or `major`,
   - **version**: optional exact version, overrides the bump,
   - **dry_run**: only show the planned version and changelog entry in the run summary, build and publish nothing,
   - **prerelease**: mark the release as a pre-release (the package is then not tagged `latest`),
   - **publish_package**: push the dmg to the GitHub package registry as `ghcr.io/congtrung6391/boox-sync:<version>` (an OCI artifact, fetched with `oras pull`),
   - **create_release**: also create a GitHub Release `v<version>` whose notes are the new changelog section, with the dmg and a `.sha256` file attached.
3. The workflow plans the version, updates `VERSION` and `CHANGELOG.md`, runs the checks, bundles adb, builds the dmg on a macOS runner, and only then pushes the release commit (`chore(release): vX.Y.Z`) and the tag to `main` and publishes. A failed build leaves no commit or tag behind. The dmg is also kept as a run artifact.

Notes:

- Every release run adds a commit to `main`. If a push from your machine is rejected afterwards, run `git pull --rebase origin main` and push again.
- If `main` has branch protection that blocks `github-actions[bot]`, allow it to bypass, or the push step fails.
- **Notarization** is not done (no Apple Developer account), so users see the unidentified-developer warning.
- **Signing.** By default CI builds are ad-hoc signed, and users re-grant permissions after each update. To keep them across releases, export your `BooxSync Local Signing` certificate from Keychain Access as a `.p12` and add the repository secrets `MACOS_CERT_P12_BASE64` (`base64 -i cert.p12`), `MACOS_CERT_PASSWORD` and `MACOS_CERT_NAME` (`BooxSync Local Signing`).
- A new package on GitHub starts private. Make it public in the package settings if anyone should be able to pull it.
- Locally, `BOOXSYNC_CHANNEL=release BOOXSYNC_VERSION=1.2.0 scripts/make-dmg.sh` builds the same dmg.

## The Android apps

`android/display` is a 16 KB fallback viewer and `android/probe` a test app, built without Gradle by `android/build-apk.sh` (needs the Android SDK command-line tools, platform 30 and build-tools 30.0.3 under `/opt/homebrew/share/android-commandlinetools`, and JDK 17). The shipped second display does not use them. The Boox's App Freeze feature can disable freshly installed apps; `adb shell pm enable <package>` brings one back.

## Troubleshooting while developing

- **Ports in use.** The second display needs 8765 and 8766 on 127.0.0.1. Quit the other BooxSync (dev or release) first.
- **Boox not found.** `adb devices -l` should list it as `device`. `unauthorized` means the Allow prompt on the Boox was not accepted; `offline` usually needs a replug.
- **Browser tabs piling up on the Boox.** The app closes its own tabs at start and stop through Chrome's DevTools socket; a crash can leave one behind, which the next start closes.
- **Stale permissions after a rebuild.** See Code signing and permissions above.
