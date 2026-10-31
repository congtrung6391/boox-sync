<p align="center"><img src="assets/logo.png" width="128" alt="BooxSync logo"></p>

# BooxSync

A Mac app for a Boox NoteX connected by USB-C (adb underneath, no Wi-Fi):

- **Files:** browse the Boox, copy files to the Mac and send files to it, with drag and drop.
- **Mirror:** see the Boox screen on the Mac, with live pen strokes while you draw (landscape).
- **Display:** use the Boox as a second Mac display over USB (virtual display, the Boox browser as the viewer, nothing installed on the Boox). Pick which windows go on it, or leave a dashboard there. The Dashboard tab is a layout editor with components such as clock, calendar, weather, to-do (local or Reminders), now playing, system stats and notes; each has several styles (analog or digital clock, ring or bar gauges, and so on), and the whole dashboard can be light or dark. Needs Screen Recording and Accessibility permission; Automation for Spotify/Music and Reminders access are optional. Weather uses Open-Meteo and needs internet on the Mac.

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

## Versioning and changelog
Versions follow [Semantic Versioning](https://semver.org/) and are chosen automatically from commit messages written as [Conventional Commits](https://www.conventionalcommits.org/): `type(scope): subject`.

| Commit | Version bump |
|---|---|
| `feat: ...` | minor (0.1.0 to 0.2.0) |
| `fix: ...`, `perf: ...`, `revert: ...` | patch (0.1.0 to 0.1.1) |
| `feat!: ...`, or `BREAKING CHANGE:` in the body | major (while below 1.0.0, a minor bump instead) |
| `docs`, `refactor` | listed in the changelog, no bump on their own |
| `build`, `ci`, `chore`, `test`, `style` | not listed, no bump |

- `VERSION` holds the current version and `CHANGELOG.md` the history. Both are updated by the release workflow, not by hand. The first section (0.1.0) was written by hand.
- Preview the next release at any time: `python3 scripts/release.py plan` (nothing is written without `--write`).
- Force a bump or an exact version with `--bump patch|minor|major` or `--version 1.0.0`. With nothing releasable since the last tag (only docs or chores), the script stops and asks for a forced bump.
- Check messages as you commit: `scripts/install-hooks.sh` enables a `commit-msg` hook that rejects anything that is not a Conventional Commit.
- Tests: `python3 scripts/test_release.py`.

## Releases
Releases are built by a manually triggered GitHub Actions workflow, `.github/workflows/release.yml`:

1. Open **Actions > Release build > Run workflow** on GitHub (on the `main` branch).
2. Choose:
   - **bump**: `auto` (from the commit messages since the last tag), or force `patch`, `minor` or `major`,
   - **version**: optional exact version, overrides the bump,
   - **dry_run**: only show the planned version and changelog entry in the run summary, build and publish nothing,
   - **prerelease**: mark the release as a pre-release (the package is then not tagged `latest`),
   - **publish_package**: push the dmg to the GitHub package registry as `ghcr.io/congtrung6391/boox-sync:<version>`,
   - **create_release**: also create a GitHub Release `v<version>` whose notes are the new changelog section, with the dmg and a `.sha256` file attached.
3. The workflow plans the version, updates `VERSION` and `CHANGELOG.md`, runs the checks, bundles adb, builds `dist/BooxSync-<version>.dmg` on a macOS runner, and only then pushes the release commit (`chore(release): vX.Y.Z`) and the tag `vX.Y.Z` to `main` and publishes. A failed build leaves no commit or tag behind. The dmg is also kept as a run artifact.

If `main` has branch protection that blocks pushes from `github-actions[bot]`, allow it to bypass, or the push step fails.

What the workflow does not do:

- **Notarization.** Without an Apple Developer account the app is not notarized, so macOS shows the unidentified-developer warning (right-click > Open, or `xattr -dr com.apple.quarantine /Applications/BooxSync.app`).
- **Signing.** By default the app is ad-hoc signed, and macOS asks for the permissions again after each update. To keep permissions across releases, sign with the same certificate every time: export your `BooxSync Local Signing` certificate from Keychain Access as a `.p12` and add these repository secrets: `MACOS_CERT_P12_BASE64` (`base64 -i cert.p12`), `MACOS_CERT_PASSWORD`, and `MACOS_CERT_NAME` (`BooxSync Local Signing`).
- **The Android apps.** `android/` holds an optional fallback and a probe, which the release does not build.

Locally, `BOOXSYNC_CHANNEL=release BOOXSYNC_VERSION=0.2.0 scripts/make-dmg.sh` produces the same dmg; without the variable it uses `VERSION`. The package registry holds the dmg as an OCI artifact, so use `oras` (see Install) to download it; the Release page is the easier route for most people.

## Dev builds and release builds
Local builds and the released app are different apps to macOS, so their permissions never mix:

| | Release (from the dmg) | Dev (`scripts/build-app.sh`) |
|---|---|---|
| Name in the Dock and Privacy lists | BooxSync | BooxSync Dev (icon with an amber DEV badge) |
| Bundle id | `dev.booxsync.app` | `dev.booxsync.app.dev` |
| Built with | `BOOXSYNC_CHANNEL=release` (the release workflow) | the default channel |

Each one asks for Screen Recording, Accessibility and Automation once. They share the Boox display ports, so run only one at a time. Saved settings (such as the dashboard layout) live per bundle id; a dev build starts with its own copy.

If you ever see duplicate BooxSync rows or permissions that do not stick, clear one identity and grant it again:
```bash
tccutil reset ScreenCapture dev.booxsync.app        # release; use dev.booxsync.app.dev for the dev build
tccutil reset Accessibility dev.booxsync.app
tccutil reset AppleEvents dev.booxsync.app
```

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
