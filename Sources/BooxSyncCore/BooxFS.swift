import Foundation

public enum BooxFSError: Error, LocalizedError, Equatable {
    case adb(String)

    public var errorDescription: String? {
        switch self {
        case .adb(let message): message
        }
    }
}

/// File operations on the Boox through adb. Nothing needs to be installed on the device.
public struct BooxFS: Sendable {
    public static let root = "/sdcard"

    public let adb: URL
    public let serial: String

    public init(adb: URL, serial: String) {
        self.adb = adb
        self.serial = serial
    }

    /// Quotes a path for the remote shell (adb joins arguments into one command string).
    public static func shellQuote(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    public func list(_ directory: String) async throws -> [BooxEntry] {
        let dir = directory.hasSuffix("/") ? directory : directory + "/"
        let out = try await run(["shell", "ls -lA \(Self.shellQuote(dir))"])
        return LsParser.parse(out, directory: directory)
    }

    /// Copies a file or folder from the Boox into `localDirectory`.
    public func pull(_ remotePath: String, to localDirectory: URL) async throws {
        try await run(["pull", remotePath, localDirectory.path])
    }

    /// Copies a file or folder from the Mac into `remoteDirectory` on the Boox.
    public func push(_ local: URL, toDirectory remoteDirectory: String) async throws {
        let dir = remoteDirectory.hasSuffix("/") ? remoteDirectory : remoteDirectory + "/"
        try await run(["push", local.path, dir])
    }

    /// Size of a file or folder on the Boox in bytes (from `du -sk`, so rounded up to KB).
    public func size(of path: String) async throws -> Int64 {
        let out = try await run(["shell", "du -sk \(Self.shellQuote(path))"])
        guard let first = out.split(whereSeparator: { $0 == "\t" || $0 == " " }).first, let kb = Int64(first) else { return 0 }
        return kb * 1024
    }

    /// Asks Android to index a pushed file so gallery and library apps see it. Best effort.
    public func scanMedia(_ path: String) async {
        _ = try? await run([
            "shell",
            "am broadcast -a android.intent.action.MEDIA_SCANNER_SCAN_FILE -d \(Self.shellQuote("file://" + path))",
        ])
    }

    /// Grabs the current screen as raw RGBA. The Boox gzips the 10 MB frame before it crosses USB,
    /// which roughly halves the time per frame (0.4 s instead of 0.75 s).
    public func captureScreen() async throws -> ScreenFrame {
        let result = try await ProcessRunner.runData(adb, ["-s", serial, "exec-out", "screencap | gzip -1"])
        guard result.status == 0 else {
            throw BooxFSError.adb(String(decoding: result.stderr, as: UTF8.self))
        }
        // The Boox firmware prints a text banner outside the gzip stream.
        var payload = result.stdout
        let banner = Data("capture from screenshot!\n".utf8)
        if payload.starts(with: banner) { payload = payload.dropFirst(banner.count) }
        guard let raw = Gzip.decompress(payload), let frame = ScreenFrame.parse(raw) else {
            throw BooxFSError.adb("Unrecognised screenshot data (\(result.stdout.count) bytes)")
        }
        return frame
    }

    public func findPenDevice() async throws -> PenDevice {
        let out = try await run(["shell", "getevent -p"])
        guard let device = PenDevice.parse(out) else { throw BooxFSError.adb("No pen digitizer found on the Boox") }
        return device
    }

    /// Streams pen positions (about 400 per second while the pen is near the screen).
    public func penSamples() -> AsyncThrowingStream<PenSample, Error> {
        let adb = self.adb, serial = self.serial
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let device = try await findPenDevice()
                    let process = Process()
                    process.executableURL = adb
                    process.arguments = ["-s", serial, "shell", "getevent -l \(Self.shellQuote(device.path))"]
                    let pipe = Pipe()
                    process.standardOutput = pipe
                    process.standardError = FileHandle.nullDevice
                    let state = PenStreamState(parser: PenEventParser(device: device))
                    pipe.fileHandleForReading.readabilityHandler = { handle in
                        let data = handle.availableData
                        if data.isEmpty {
                            handle.readabilityHandler = nil
                            continuation.finish()
                            return
                        }
                        for sample in state.consume(data) { continuation.yield(sample) }
                    }
                    continuation.onTermination = { _ in
                        pipe.fileHandleForReading.readabilityHandler = nil
                        if process.isRunning { process.terminate() }
                    }
                    try process.run()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public static let displayPackage = "dev.booxsync.display"

    /// Installs (if needed) and starts the BooxDisplay app, and forwards its port to the Mac.
    /// `pm enable` is needed because the Boox "App Freeze" feature disables apps it has not seen used.
    public func startDisplayApp(apk: URL?) async throws {
        let installed = try await run(["shell", "pm list packages \(Self.displayPackage)"]).contains(Self.displayPackage)
        if !installed {
            guard let apk else { throw BooxFSError.adb("BooxDisplay is not installed on the Boox and no apk was provided") }
            try await run(["install", "-r", "--no-incremental", apk.path])
        }
        try await run(["forward", "tcp:\(DisplayProtocol.port)", "tcp:\(DisplayProtocol.port)"])
        // The freeze service can disable the app again just after install or after it was closed,
        // and `am start` still exits 0 with an "Error:" message, so check the text and retry.
        var lastOutput = ""
        for attempt in 0..<4 {
            if attempt > 0 { try await Task.sleep(for: .seconds(1.5)) }
            _ = try? await run(["shell", "pm enable \(Self.displayPackage)"])
            lastOutput = try await run(["shell", "am start -n \(Self.displayPackage)/.MainActivity"])
            if !lastOutput.contains("Error") { return }
        }
        throw BooxFSError.adb("Could not start BooxDisplay: \(lastOutput.trimmingCharacters(in: .whitespacesAndNewlines))")
    }

    /// Opens the display page in the Boox browser through `adb reverse` (no app install, no Wi-Fi).
    public func openWebDisplay() async throws {
        for port in [DisplayPage.httpPort, DisplayPage.webSocketPort] {
            try await run(["reverse", "tcp:\(port)", "tcp:\(port)"])
        }
        // A fresh browser process: old tabs from earlier runs would also reconnect and compete for tiles.
        _ = try? await run(["shell", "am force-stop org.chromium.chrome"])
        let url = "http://localhost:\(DisplayPage.httpPort)/?t=\(Int(Date().timeIntervalSince1970))"
        try await run(["shell", "am start -a android.intent.action.VIEW -d \(Self.shellQuote(url))"])
    }

    /// A tap counts as a user gesture, which is what makes the Boox browser hide its toolbars.
    public func tap(x: Int, y: Int) async throws {
        try await run(["shell", "input tap \(x) \(y)"])
    }

    public func goHome() async throws {
        try await run(["shell", "input keyevent KEYCODE_HOME"])
    }

    public func closeWebDisplay() async {
        for port in [DisplayPage.httpPort, DisplayPage.webSocketPort] {
            _ = try? await run(["reverse", "--remove", "tcp:\(port)"])
        }
    }

    public func makeDirectory(_ path: String) async throws {
        try await run(["shell", "mkdir -p \(Self.shellQuote(path))"])
    }

    public func rename(_ path: String, to newName: String) async throws {
        let parent = (path as NSString).deletingLastPathComponent
        let target = parent + "/" + newName
        try await run(["shell", "mv \(Self.shellQuote(path)) \(Self.shellQuote(target))"])
    }

    public func delete(_ path: String) async throws {
        try await run(["shell", "rm -rf \(Self.shellQuote(path))"])
    }

    @discardableResult
    private func run(_ arguments: [String]) async throws -> String {
        let result = try await ProcessRunner.run(adb, ["-s", serial] + arguments)
        guard result.status == 0 else {
            let message = (result.stderr + result.stdout).trimmingCharacters(in: .whitespacesAndNewlines)
            throw BooxFSError.adb(message.isEmpty ? "adb exited with status \(result.status)" : message)
        }
        return result.stdout
    }
}

/// Splits the getevent byte stream into lines and feeds them to the parser. Called from one handler thread.
private final class PenStreamState: @unchecked Sendable {
    private let lock = NSLock()
    private var parser: PenEventParser
    private var buffer = Data()

    init(parser: PenEventParser) {
        self.parser = parser
    }

    func consume(_ data: Data) -> [PenSample] {
        lock.lock(); defer { lock.unlock() }
        buffer.append(data)
        var samples: [PenSample] = []
        while let newline = buffer.firstIndex(of: 0x0a) {
            let line = String(decoding: buffer[buffer.startIndex..<newline], as: UTF8.self)
            buffer.removeSubrange(buffer.startIndex...newline)
            if let sample = parser.feed(line) { samples.append(sample) }
        }
        return samples
    }
}
