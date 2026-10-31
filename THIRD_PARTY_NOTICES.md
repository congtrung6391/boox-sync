# Third-party notices

BooxSync itself is MIT licensed (see LICENSE). It uses or bundles the following.

## Android platform-tools (adb)
The app bundle includes the `adb` binary from Google's Android SDK Platform-Tools, licensed under the
Apache License 2.0. Google's notice file is copied into the app at
`BooxSync.app/Contents/Resources/licenses/android-platform-tools-NOTICE.txt`.
Source and licence: https://developer.android.com/tools/releases/platform-tools

## Open-Meteo (weather data)
The weather component shows data from Open-Meteo.com, licensed under CC BY 4.0.
Weather data by [Open-Meteo.com](https://open-meteo.com/). Geocoding by Open-Meteo.

## Apple frameworks and SF Symbols
The app uses system frameworks (SwiftUI, ScreenCaptureKit, EventKit and others) and SF Symbols through the
operating system. The private CGVirtualDisplay interface is looked up at run time; it is not shipped or
redistributed by this project.

## Not bundled
Spotify and Music track details are read from the running apps on your Mac and are only shown locally.
scrcpy was used during early testing and is not part of the app.
