import Foundation
import CoreGraphics
import BooxSyncCore

// Plain assertion runner: `swift run CoreChecks`. Replace with XCTest once full Xcode is installed.
let fm0 = FileManager.default
var failures = 0
func check(_ name: String, _ condition: Bool) {
    print("\(condition ? "ok  " : "FAIL") \(name)")
    if !condition { failures += 1 }
}

let connected = """
List of devices attached
980DDC19               device usb:17825792X product:BOOX model:NoteX device:BOOX transport_id:1

"""
check("parses connected device",
      AdbParser.parseDevices(connected) ==
        [AdbDevice(serial: "980DDC19", state: .device, model: "NoteX", product: "BOOX", transportId: "1")])

let mixed = """
* daemon started successfully
List of devices attached
AAA    unauthorized usb:1X transport_id:2
BBB    offline transport_id:3
"""
check("parses unauthorized and offline", AdbParser.parseDevices(mixed).map(\.state) == [.unauthorized, .offline])
check("empty list", AdbParser.parseDevices("List of devices attached\n\n").isEmpty)
check("daemon banner ignored", AdbParser.parseDevices("* daemon not running; starting now at tcp:5037\n").isEmpty)
check("detects ONYX vendor", UsbProbe.containsOnyx("  \"USB Vendor Name\" = \"ONYX\"\n"))
check("ignores other vendors", !UsbProbe.containsOnyx("  \"USB Vendor Name\" = \"Apple\"\n"))

let sample = """
total 12
drwxrwx--x 3 root sdcard_rw 4096 2026-10-30 12:00 Android
-rw-rw---- 1 root sdcard_rw 102973 2026-10-31 10:46 My Book (2).pdf
lrwxrwxrwx 1 root root 21 2026-10-31 10:46:12 link -> /storage/x
-rw-rw---- 1 root sdcard_rw 5 2026-10-31 10:46 it's  odd.txt
"""
let entries = LsParser.parse(sample, directory: "/sdcard")
check("ls parser count", entries.count == 4)
check("ls parser dir", entries[0].isDirectory && entries[0].size == nil && entries[0].path == "/sdcard/Android")
check("ls parser name with spaces", entries[1].name == "My Book (2).pdf" && entries[1].size == 102973)
check("ls parser symlink target stripped", entries[2].name == "link" && entries[2].isSymlink)
check("ls parser keeps double space and quote", entries[3].name == "it's  odd.txt")
check("ls parser date", entries[1].modified != nil)
check("shell quote", BooxFS.shellQuote("a'b c") == "'a'\\''b c'")

var fake = Data("capture from screenshot!\n".utf8)
for v in [2, 2, 1, 0] { fake.append(contentsOf: [UInt8(v), 0, 0, 0]) }
fake.append(Data(repeating: 7, count: 2 * 2 * 4))
let parsed = ScreenFrame.parse(fake)
check("screen frame parse", parsed?.width == 2 && parsed?.height == 2 && parsed?.rgba.count == 16 && parsed?.rgba.first == 7)
check("screen frame rejects junk", ScreenFrame.parse(Data("hello".utf8)) == nil)

let gz = Data([0x1f, 0x8b, 0x08, 0x00, 0, 0, 0, 0, 0x04, 0x03, 0xcb, 0x48, 0xcd, 0xc9, 0xc9, 0x07, 0x00, 0x86, 0xa6, 0x10, 0x36, 0x05, 0x00, 0x00, 0x00])
check("gzip decompress", Gzip.decompress(gz).map { String(decoding: $0, as: UTF8.self) } == "hello")
check("gzip rejects junk", Gzip.decompress(Data("nope nope nope".utf8)) == nil)

let eventsP = """
add device 1: /dev/input/event4
  name:     "cyttsp5_mt"
add device 2: /dev/input/event3
  name:     "onyx_emp_Wacom I2C Digitizer"
  events:
    KEY (0001): 0141  0142* 014a* 014b  014c  0152* 0153
    ABS (0003): 0000  : value 17526, min 0, max 20966, fuzz 0, flat 0, resolution 0
                0001  : value 12963, min 0, max 15725, fuzz 0, flat 0, resolution 0
                0018  : value 1084, min 0, max 4095, fuzz 0, flat 0, resolution 0
"""
let pen = PenDevice.parse(eventsP)
check("pen device discovery", pen == PenDevice(path: "/dev/input/event3", maxX: 20966, maxY: 15725))
var penParser = PenEventParser(device: pen!)
var emitted: [PenSample] = []
for line in ["EV_KEY       BTN_TOOL_BRUSH       DOWN", "EV_ABS       ABS_X                00002c2b", "EV_ABS       ABS_Y                000035d3",
             "EV_KEY       BTN_TOUCH            DOWN", "EV_SYN       SYN_REPORT           00000000",
             "EV_ABS       ABS_X                00002c3d", "EV_SYN       SYN_REPORT           00000000",
             "EV_KEY       BTN_TOUCH            UP", "EV_SYN       SYN_REPORT           00000000", "EV_SYN       SYN_REPORT           00000000"] {
    if let sample = penParser.feed(line) { emitted.append(sample) }
}
check("pen parser emits one sample per report with changes", emitted.count == 3)
check("pen parser touch states", emitted.map(\.touching) == [true, true, false])
check("pen parser normalises", abs(emitted[0].x - 11307.0 / 20966.0) < 1e-9)
let mid = PenMapping.screenPoint(PenSample(x: 0.25, y: 0.1, touching: true, erasing: false), frameWidth: 1872, frameHeight: 1404)
check("pen mapping rotates 180 in landscape", mid?.x == 0.75 && mid?.y == 0.9)
check("pen mapping disabled in portrait", PenMapping.screenPoint(PenSample(x: 0, y: 0, touching: true, erasing: false), frameWidth: 1404, frameHeight: 1872) == nil)

let monitorUnderTest = SystemMonitor()
_ = monitorUnderTest.sample()
Thread.sleep(forTimeInterval: 1.2)
let res = monitorUnderTest.sample()
check("resources: cpu 0...1 (\(Int(res.cpu * 100))%)", (0...1).contains(res.cpu))
check("resources: memory used \(res.memoryUsed >> 20) MB of \(res.memoryTotal >> 20) MB", res.memoryUsed > 0 && res.memoryUsed <= res.memoryTotal)
check("resources: disk \(res.diskUsed >> 30) GB of \(res.diskTotal >> 30) GB", res.diskTotal > 0 && res.diskUsed <= res.diskTotal)
check("resources: network rates are non-negative (down \(Int(res.networkDown)) B/s)", res.networkDown >= 0 && res.networkUp >= 0)
print("info battery: \(res.batteryPercent.map(String.init) ?? "none") charging \(res.batteryCharging)")
let np = NowPlayingProvider.parse("Song\tArtist\tAlbum\tplaying\thttps://x/y.jpg\t215000\t42", source: "Spotify")
check("now playing parse", np?.title == "Song" && np?.isPlaying == true && np?.duration == 215 && np?.position == 42 && np?.artworkURL != nil)
check("now playing rejects short", NowPlayingProvider.parse("stopped", source: "Spotify") == nil)

let sampleWindows = WindowMover.listWindows()
check("window list returns app windows (\(sampleWindows.count))", !sampleWindows.isEmpty)
for w in sampleWindows.prefix(5) { print("info window \(w.id) \(w.appName) - \(w.title.prefix(40)) \(Int(w.bounds.width))x\(Int(w.bounds.height))") }
print("info accessibility trusted for this process: \(WindowMover.isTrusted(prompt: false))")

let fm = FileManager.default
let adb = AdbLocator.find(bundleResources: nil, environmentPath: "/nonexistent", fileManager: fm)
check("locates adb (homebrew or /usr/local)", adb != nil || !fm.isExecutableFile(atPath: "/opt/homebrew/bin/adb"))

if CommandLine.arguments.contains("--session-test") {
    Task { @MainActor in
        let monitor = DeviceMonitor()
        await monitor.refresh()
        guard case .connected(let device) = monitor.status, let adb = monitor.adbURL else { print("no device"); exit(1) }
        let tabFS = BooxFS(adb: adb, serial: device.serial)
        print("tabs before: \(await tabFS.displayTabIDs().count)")
        let session = SecondDisplaySession(fs: tabFS)
        session.onStatus = { print("status: \($0)") }
        session.onStats = { if $0.tilesPerSecond > 0 { print("stats: \($0.width)x\($0.height) \($0.tilesPerSecond) tiles, \($0.kilobytesPerSecond) KB in the last second") } }
        do {
            try await session.start()
            print("session running; screenshot the Boox now")
            print("tabs while running: \(await tabFS.displayTabIDs().count)")
            try await Task.sleep(for: .seconds(Double(CommandLine.arguments.last.flatMap(Double.init) ?? 25)))
            await session.stop()
            print("tabs after stop: \(await tabFS.displayTabIDs().count)")
            print("ok   session test done")
            exit(0)
        } catch {
            print("FAIL \(error)")
            await session.stop()
            exit(1)
        }
    }
    dispatchMain()
}

if CommandLine.arguments.contains("--vd-test") {
    do {
        let before = Set((0..<8).compactMap { _ in CGMainDisplayID() })
        _ = before
        let display = try VirtualDisplay(width: 1872, height: 1302)
        print("virtual display id \(display.displayID)")
        Task { @MainActor in
            let ok = await display.activateNativeMode()
            print("activateNativeMode: \(ok)")
        }
        Thread.sleep(forTimeInterval: 0.01)
        RunLoop.current.run(until: Date().addingTimeInterval(1.5))
        var count: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &count)
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetActiveDisplayList(count, &ids, &count)
        for id in ids { let b = CGDisplayBounds(id); print("display \(id): \(Int(b.width))x\(Int(b.height)) at \(Int(b.origin.x)),\(Int(b.origin.y))\(id == display.displayID ? "  <- virtual" : "")") }
        if let mode = CGDisplayCopyDisplayMode(display.displayID) {
            print("virtual display mode: \(mode.width)x\(mode.height) points, \(mode.pixelWidth)x\(mode.pixelHeight) pixels")
        }
        if let all = CGDisplayCopyAllDisplayModes(display.displayID, [kCGDisplayShowDuplicateLowResolutionModes: true] as CFDictionary) as? [CGDisplayMode] {
            for m in all { print("  available \(m.width)x\(m.height) px \(m.pixelWidth)x\(m.pixelHeight) @\(m.refreshRate)") }
        }
        print("screen capture permission: \(CGPreflightScreenCaptureAccess())")
        Thread.sleep(forTimeInterval: 2)
        display.destroy()
        print("ok   virtual display created and destroyed")
        exit(0)
    } catch {
        print("FAIL \(error)"); exit(1)
    }
}

if CommandLine.arguments.contains("--web-test") {
    Task { @MainActor in
        let monitor = DeviceMonitor()
        await monitor.refresh()
        guard case .connected(let device) = monitor.status, let adb = monitor.adbURL else { print("no device"); exit(1) }
        let fs = BooxFS(adb: adb, serial: device.serial)
        let server = DisplayServer()
        let latest = LatestHello()
        server.onHello = { latest.set($0) }
        server.onText = { print("page: \($0)") }
        do {
            try server.start()
            try await fs.openWebDisplay()
            for _ in 0..<30 where latest.get() == nil { try await Task.sleep(for: .milliseconds(200)) }
            guard let first = latest.get() else { print("FAIL page never said hello"); exit(1) }
            print("page hello \(first.width)x\(first.height) dpr \(first.dpr)")
            try await fs.tap(x: 900, y: 700)
            try await Task.sleep(for: .seconds(2))
            let info = latest.get()!
            print("after tap \(info.width)x\(info.height)")
            let differ = TileDiffer()
            let w = info.width, h = info.height
            var frame = [UInt8](repeating: 255, count: w * h * 4)
            func paint(_ x0: Int, _ y0: Int, _ pw: Int, _ ph: Int, _ g: UInt8) {
                for y in y0..<min(h, y0 + ph) { for x in x0..<min(w, x0 + pw) { let i = (y * w + x) * 4; frame[i] = g; frame[i+1] = g; frame[i+2] = g } }
            }
            for x in 0..<w { paint(x, 0, 1, 40, UInt8(x * 255 / w)) }
            paint(0, 0, w, 4, 0); paint(0, h - 4, w, 4, 0); paint(0, 0, 4, h, 0); paint(w - 4, 0, 4, h, 0)
            func send() -> Int {
                let tiles = frame.withUnsafeBufferPointer { differ.process(bgra: $0.baseAddress!, width: w, height: h, bytesPerRow: w * 4) }
                for t in tiles { server.sendTile(x: t.x, y: t.y, width: t.width, height: t.height, png: t.png) }
                return tiles.reduce(0) { $0 + $1.png.count }
            }
            let t0 = Date()
            let fullBytes = send()
            print("full frame: \(fullBytes) bytes of PNG, encoded in \(String(format: "%.3f", Date().timeIntervalSince(t0))) s")
            try await Task.sleep(for: .seconds(1))
            var lastX = 100
            var moved = 0
            for step in 0..<12 {
                paint(lastX, 300, 200, 200, 255)
                lastX = 100 + step * 120
                paint(lastX, 300, 200, 200, 0)
                moved += send()
                try await Task.sleep(for: .milliseconds(400))
            }
            print("moving square: \(moved) PNG bytes in 12 updates")
            print("ok   web test done (look at the Boox)")
            try await Task.sleep(for: .seconds(2))
            await fs.closeWebDisplay()
            server.stop()
            exit(0)
        } catch {
            print("FAIL \(error)")
            exit(1)
        }
    }
    dispatchMain()
}

if CommandLine.arguments.contains("--display-test") {
    Task { @MainActor in
        let monitor = DeviceMonitor()
        await monitor.refresh()
        guard case .connected(let device) = monitor.status, let adb = monitor.adbURL else { print("no device"); exit(1) }
        let fs = BooxFS(adb: adb, serial: device.serial)
        let apk = URL(fileURLWithPath: "android/display/build/BooxDisplay.apk")
        do {
            try await fs.startDisplayApp(apk: apk)
            var link: DisplayLink?
            for _ in 0..<20 {
                link = try? DisplayLink.connect()
                if link != nil { break }
                try await Task.sleep(for: .milliseconds(500))
            }
            guard let link else { print("FAIL could not connect"); exit(1) }
            print("connected, Boox view is \(link.width)x\(link.height)")
            let w = link.width, h = link.height
            // Full frame: white with a gradient bar and a frame.
            var full = Data(repeating: 255, count: w * h)
            for y in 0..<h { for x in 0..<w {
                if y < 40 { full[y * w + x] = UInt8(x * 255 / w) }
                if x < 6 || x >= w - 6 || y < 6 || y >= h - 6 { full[y * w + x] = 0 }
            } }
            let t0 = Date()
            try link.send(x: 0, y: 0, width: w, height: h, gray: full)
            print("full frame sent in \(String(format: "%.3f", Date().timeIntervalSince(t0))) s")
            // Moving square as small tiles.
            let size = 200
            let tile = Data(repeating: 0, count: size * size)
            let white = Data(repeating: 255, count: size * size)
            var lastX = 100
            for step in 0..<20 {
                try link.send(x: lastX, y: 300, width: size, height: size, gray: white)
                lastX = 100 + step * 60
                try link.send(x: lastX, y: 300, width: size, height: size, gray: tile)
                try await Task.sleep(for: .milliseconds(300))
            }
            print("ok   display test done")
            link.close()
            exit(0)
        } catch {
            print("FAIL \(error)")
            exit(1)
        }
    }
    dispatchMain()
}

if CommandLine.arguments.contains("--live") {
    // MainActor work needs a running main queue, so exit from inside the task.
    Task { @MainActor in
        let monitor = DeviceMonitor()
        await monitor.refresh()
        print("live status: \(monitor.status)")
        if case .connected(let device) = monitor.status, let adb = monitor.adbURL {
            await liveFileChecks(BooxFS(adb: adb, serial: device.serial))
        }
        exit(failures == 0 ? 0 : 1)
    }
    dispatchMain()
}

exit(failures == 0 ? 0 : 1)

@MainActor
func liveFileChecks(_ fs: BooxFS) async {
    let remote = "/sdcard/booxsync_check"
    let tmp = fm0.temporaryDirectory.appendingPathComponent("booxsync-check-\(UUID().uuidString)")
    try? fm0.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? fm0.removeItem(at: tmp) }
    do {
        let started0 = Date()
        let frame = try await fs.captureScreen()
        check("live screen capture \(frame.width)x\(frame.height) in \(String(format: "%.2f", Date().timeIntervalSince(started0))) s",
              frame.width * frame.height * 4 == frame.rgba.count && frame.width >= 1000)
        var count = 0
        var sawTouch = false
        let streamTask = Task {
            for try await sample in fs.penSamples() { count += 1; if sample.touching { sawTouch = true } }
        }
        try await Task.sleep(for: .seconds(3))
        streamTask.cancel()
        print("info pen stream samples in 3 s (hover or draw to see >0): \(count), touch seen: \(sawTouch)")
        let root = try await fs.list(BooxFS.root)
        check("live list /sdcard has Books", root.contains { $0.name == "Books" && $0.isDirectory })

        try? await fs.delete(remote)
        try await fs.makeDirectory(remote)
        let name = "it's a test (1) é.txt"
        let local = tmp.appendingPathComponent(name)
        try Data("hello boox".utf8).write(to: local)
        try await fs.push(local, toDirectory: remote)
        let listed = try await fs.list(remote)
        check("live push shows file with odd name", listed.contains { $0.name == name && $0.size == 10 })

        let back = tmp.appendingPathComponent("back")
        try fm0.createDirectory(at: back, withIntermediateDirectories: true)
        try await fs.pull(remote + "/" + name, to: back)
        let pulled = try? String(contentsOf: back.appendingPathComponent(name), encoding: .utf8)
        check("live pull round trip", pulled == "hello boox")

        try await fs.rename(remote + "/" + name, to: "renamed file.txt")
        check("live rename", try await fs.list(remote).contains { $0.name == "renamed file.txt" })

        let folder = tmp.appendingPathComponent("a folder")
        try fm0.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: folder.appendingPathComponent("inner.txt"))
        try await fs.push(folder, toDirectory: remote)
        check("live push folder", try await fs.list(remote + "/a folder").contains { $0.name == "inner.txt" })

        try await fs.delete(remote)
        check("live delete", (try? await fs.list(remote)) == nil)

        // Progress and cancellation on a larger file.
        try await fs.makeDirectory(remote)
        let big = tmp.appendingPathComponent("big.bin")
        // Random data: adb compresses zeros, which would finish far too fast to observe.
        _ = try await ProcessRunner.run(URL(fileURLWithPath: "/bin/dd"), ["if=/dev/urandom", "of=\(big.path)", "bs=1048576", "count=300"])
        check("local size", LocalFS.size(of: big) == 300 * 1024 * 1024)
        let pushTask = Task { try await fs.push(big, toDirectory: remote) }
        try await Task.sleep(for: .seconds(3))
        let partial = try await fs.size(of: remote + "/big.bin")
        check("remote size grows during push (\(partial / 1024 / 1024) MB)", partial > 10 * 1024 * 1024 && partial < 300 * 1024 * 1024)
        let started = Date()
        pushTask.cancel()
        let outcome = await pushTask.result
        check("cancel stops push quickly", Date().timeIntervalSince(started) < 3)
        if case .success = outcome { check("push was cancelled", false) } else { check("push threw after cancel", true) }
        try? await fs.delete(remote)
    } catch {
        check("live file checks threw: \(error)", false)
        try? await fs.delete(remote)
    }
}

final class LatestHello: @unchecked Sendable {
    private let lock = NSLock()
    private var value: DisplayClientInfo?
    func set(_ v: DisplayClientInfo) { lock.lock(); value = v; lock.unlock() }
    func get() -> DisplayClientInfo? { lock.lock(); defer { lock.unlock() }; return value }
}
