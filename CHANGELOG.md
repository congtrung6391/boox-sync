# Changelog

All notable changes to BooxSync are documented here. From the next release on, this file is written by
`scripts/release.py` from [Conventional Commit](https://www.conventionalcommits.org/) messages when a release is
made. The 0.1.0 section below was written by hand for the first release.

This project follows [Semantic Versioning](https://semver.org/).

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
