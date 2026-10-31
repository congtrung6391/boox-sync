# Changelog

All notable changes to BooxSync are documented here. From the next release on, this file is written by
`scripts/release.py` from [Conventional Commit](https://www.conventionalcommits.org/) messages when a release is
made. The 0.1.0 section below was written by hand for the first release.

This project follows [Semantic Versioning](https://semver.org/).

## [1.1.1] - 2026-10-31

### Features

- add demo mode for screenshots and fix toolbar tab placement on macOS 26 ([eaaab93](https://github.com/congtrung6391/boox-sync/commit/eaaab9341dcdc146dae88cd48d1fe3d47afa3cba))

### Bug fixes

- reopen the main window from the menu bar or by relaunching the app ([cfa1c0b](https://github.com/congtrung6391/boox-sync/commit/cfa1c0b7b0e91e60f3043cd3c2a26fc35b6724cb))

### Reverts

- remove the demo mode and screenshot script ([b45f077](https://github.com/congtrung6391/boox-sync/commit/b45f0771cc12f880b21326de0b47ced719a33628))

### Documentation

- remove the dashboard screenshot ([701283a](https://github.com/congtrung6391/boox-sync/commit/701283a68cd3526a4062b5c0f4b44e8ef2ef5596))
- add screenshots to the README ([458d799](https://github.com/congtrung6391/boox-sync/commit/458d79963c88dfbbdf4d64b661fdde69929f4742))
- write the README for end users and move developer instructions to docs/DEVELOPMENT.md ([4c2d91f](https://github.com/congtrung6391/boox-sync/commit/4c2d91f3ff6f35478f4bc663dc28fac69409efc0))

## [1.1.0] - 2026-10-31

### Features

- **dashboard:** add a dark theme ([ddfc211](https://github.com/congtrung6391/boox-sync/commit/ddfc2119b08f1d405388aeff7e0c0b11b7ed3b42))

## [1.0.2] - 2026-10-31

### Bug fixes

- **build:** separate bundle ids for dev and release builds ([129df95](https://github.com/congtrung6391/boox-sync/commit/129df95f4e1290058a92fada159c873495a8a9b5))

## [1.0.1] - 2026-10-31

No user-facing changes.

## [0.1.0] - 2026-10-31

First release.

### Features

- **Files:** browse the Boox over USB, copy files to and from the Mac, drag and drop, transfer queue with progress and cancel.
- **Mirror:** see the Boox screen on the Mac with grayscale, darkness and contrast controls, live pen strokes, copy and save.
- **Display:** use the Boox as a second Mac display with no app installed on it (virtual display, tiles over a loopback WebSocket, Boox browser as the viewer).
- **Window picker:** send any window to the Boox display, bring one to the top, pull windows back, optional Mac pointer.
- **Dashboard:** a grid layout editor with 12 components (clock, date, calendar, weather, to-do, now playing, CPU, memory, disk, network, battery, note), 3-4 styles each, and presets.
- Weather from Open-Meteo, to-do from a local list or Apple Reminders, now playing from Spotify or Music.
- Bundled adb, app icon, dmg build, stable local code signing, MIT licence.
