# Changelog

All notable changes to BooxSync are documented here. From the next release on, this file is written by
`scripts/release.py` from [Conventional Commit](https://www.conventionalcommits.org/) messages when a release is
made. The 0.1.0 section below was written by hand for the first release.

This project follows [Semantic Versioning](https://semver.org/).

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
