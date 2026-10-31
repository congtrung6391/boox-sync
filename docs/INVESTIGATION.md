# Boox Note Air ↔ macOS: screencast and file sharing (investigation)

Date: 2026-10-31. Host: MacBook Pro, macOS 26.4, three Thunderbolt/USB4 ports (40 Gb/s), no device connected. `adb` and `scrcpy` are not installed.

## Key finding: Thunderbolt does not apply to the Boox
The Note Air has a USB-C port that runs as a plain USB device. Reviews say the Air 3 / Air 3 C port is USB 2.0 only. I found no explicit USB 3 spec for the Air4 C or Air5 C. A Thunderbolt cable plugged into the Mac gives you a USB 2.0 link, about 480 Mb/s at best, and the Mac's Thunderbolt ports only matter as ordinary USB-C ports. There is no "Thunderbolt networking" with the tablet. Wi-Fi is the realistic alternative for bulk transfer.

## Which Note Air?
"Note Air" covers several generations. Confirm the exact model in Settings > About.

| Model | Panel | Android | Notes |
|---|---|---|---|
| Note Air (2020) | 10.3" Carta HD, 1872x1404, 227 ppi | 10 | Wacom pen. Modes: Normal, Speed, A2, X |
| Note Air3 | 10.3" Carta 1200, 227 ppi | 12 | BSR refresh, four modes. USB 2.0 |
| Note Air3 C / Air4 C | 10.3" Kaleido 3 colour | 12 / 13 | Air4 C is the same chassis as Air3 C, with more RAM |
| Note Air5 C | 10.3" Kaleido 3, B/W 2480x1860 (300 ppi), colour 1240x930 | 15 (one source says 13) | EMR stylus, keyboard cover |

## E-ink implications for screencast
- Refresh is slow and ghosting is heavy in the fast modes (A2/X). Mirroring video will look poor.
- Mirroring the Boox to the Mac, which is what scrcpy does, works at the Android level and should be fine, apart from the tablet's own refresh lag.
- Mirroring a Mac to the Boox, using it as a second monitor, means a laggy, low-fps display. Use A2/X refresh mode, grayscale, and static content.
- If scrcpy lags, lower `--max-size` and bitrate (`-b`).
- No Boox-specific scrcpy reports were found. Treat the combination as untested until we try it.

## Screencast options (Boox to Mac)
1. **scrcpy over USB.** Enable Developer options, then USB debugging. `brew install scrcpy android-platform-tools`, then `scrcpy --max-size 1280 -b 2M`. Needs `adb devices` to list the tablet. Boox's modified Android may need the debugging prompt accepted on the device.
2. **scrcpy over Wi-Fi.** `adb tcpip 5555`, then `adb connect <ip>:5555`.
3. **Boox's built-in screen mirroring or projection.** Per the NoteAir2 manual, the computer and the Boox must be on the same Wi-Fi network, and some computers aren't supported. The help-center article was not reachable, so the steps are unverified.
4. **AnyDesk and similar.** One MobileRead user with a Mac tried it, and the result is unknown.

## File sharing options
1. **MTP over USB.** Set the USB mode to file transfer on the tablet. macOS has no native MTP support, so use Google's Android File Transfer (poorly maintained), MacDroid (lists a Boox page, MTP and ADB) or Conduit.
2. **adb push / pull.** Scriptable, which suits a sync tool. `adb push file /sdcard/Books/` and `adb pull /sdcard/Notes/ ./`. Works over USB or Wi-Fi. This is probably the best base for a "booxsync" tool.
3. **BOOXDrop (built in).** Wi-Fi transfer from a browser on the Mac, no cable.
4. **Syncing apps.** For example Syncthing, if Android apps can be installed. Not researched.

## Suggested next steps
1. Confirm the exact Boox model and Android version.
2. Install `scrcpy` and `adb`, connect the Boox by USB-C, and check `adb devices`.
3. Test scrcpy quality and refresh behaviour, and time an `adb push` of a large file to measure real throughput.
4. Decide whether the sync tool is built on adb, BOOXDrop or Syncthing.

## Sources
- [Boox Note Air review (MakeUseOf mirror)](https://onyxboox.com/review/ebook-onyx-boox-noteair-makeuseof)
- [BOOX NoteAir2 User Manual](https://onyxboox.com/files/manuals/BOOX_NoteAir2Series_User_Manual_(20220416).pdf)
- [Notebookcheck: Note Air 3 C review (USB 2.0)](https://www.notebookcheck.com/Test-Onyx-Boox-Note-Air-3-C-E-Ink-Tablet-mit-Farbdisplay-Stylus-Bedienung-und-Android.762546.0.html)
- [Liliputing: Note Air4 C](https://liliputing.com/onyx-boox-note-air4-c-is-a-10-3-inch-e-ink-color-tablet-with-6gb-ram-and-android-13/)
- [Liliputing: Note Air5 C](https://liliputing.com/onyx-boox-note-air5-c-is-a-10-3-inch-color-e-ink-tablet-with-pen-and-keyboard-support/)
- [MobileRead: mirroring thread](https://mobileread.com/forums/showthread.php?p=4418358)
- [scrcpy on macOS guide](https://fossbytes.com/mirror-android-phone-to-pc-windows-macos/)
- [adb file transfer guide](https://dev.to/jsuryakt/efficient-file-transfer-from-android-to-mac-using-adb-o0i)
- [MacDroid](https://www.macdroid.app/llms.txt)
