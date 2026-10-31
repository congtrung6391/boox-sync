import Foundation
import CoreGraphics

public enum SecondDisplayError: Error, LocalizedError {
    case browserNeverConnected
    case badSize(Int, Int)

    public var errorDescription: String? {
        switch self {
        case .browserNeverConnected:
            "The Boox browser did not open the display page. Check that the Boox is awake and USB Debug Mode is on."
        case .badSize(let w, let h):
            "The Boox browser reported an unusable size (\(w)x\(h))"
        }
    }
}

/// The Boox as a second Mac display: virtual display -> capture -> changed tiles -> WebSocket -> Boox browser.
public final class SecondDisplaySession: @unchecked Sendable {
    public struct Stats: Sendable {
        public var width = 0
        public var height = 0
        public var tilesPerSecond = 0
        public var kilobytesPerSecond = 0

        public init(width: Int = 0, height: Int = 0, tilesPerSecond: Int = 0, kilobytesPerSecond: Int = 0) {
            self.width = width
            self.height = height
            self.tilesPerSecond = tilesPerSecond
            self.kilobytesPerSecond = kilobytesPerSecond
        }
    }

    /// Whether the Mac pointer is drawn into the Boox picture. Change it any time with `setShowsCursor`.
    public private(set) var showsCursor = true

    public var onStatus: (@Sendable (String) -> Void)?
    public var onStats: (@Sendable (Stats) -> Void)?

    private let fs: BooxFS
    private let server = DisplayServer()
    private let capture = ScreenCapture()
    private let differ = TileDiffer()
    private let lock = NSLock()
    private var display: VirtualDisplay?
    private var latest: DisplayClientInfo?
    private var running = false
    private var restartTask: Task<Void, Never>?
    private var statsTask: Task<Void, Never>?
    private var tileCount = 0
    private var byteCount = 0
    private var size = (width: 0, height: 0)

    public init(fs: BooxFS) {
        self.fs = fs
    }

    public func setShowsCursor(_ show: Bool) async {
        locked { showsCursor = show }
        await capture.setShowsCursor(show)
    }

    /// The virtual display while the session runs.
    public var virtualDisplayID: CGDirectDisplayID? { locked { display?.displayID } }

    public func start() async throws {
        guard ScreenCapture.requestPermission() else { throw ScreenCaptureError.permissionDenied }
        onStatus?("Screen Recording permission OK")

        server.onHello = { [weak self] info in self?.handleHello(info) }
        server.onClientChange = { [weak self] connected in
            if connected { self?.resend() }
        }
        try server.start()
        do {
            onStatus?("Opening the display page on the Boox...")
            try await fs.openWebDisplay()
            let first = try await waitForHello(after: nil, timeout: 12)
            onStatus?("Going fullscreen on the Boox...")
            try? await fs.tap(x: 900, y: 700)
            let settled = (try? await waitForHello(after: first, timeout: 3)) ?? first

            locked { running = true }
            try await startPipeline(width: settled.width, height: settled.height)
            statsTask = Task { [weak self] in await self?.reportStats() }
        } catch {
            await stop()
            throw error
        }
    }

    public func stop() async {
        locked { running = false }
        restartTask?.cancel()
        statsTask?.cancel()
        await capture.stop()
        display?.destroy()
        display = nil
        server.stop()
        await fs.closeDisplayTabs()
        await fs.closeWebDisplay()
        try? await fs.goHome()
        onStatus?("Stopped")
    }

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    // MARK: Pipeline

    private func startPipeline(width: Int, height: Int) async throws {
        guard (320...4096).contains(width), (240...4096).contains(height) else { throw SecondDisplayError.badSize(width, height) }
        onStatus?("Creating the virtual display (\(width)x\(height))...")
        let created = try VirtualDisplay(width: width, height: height)
        display = created
        _ = await created.activateNativeMode()
        locked { size = (width, height) }
        differ.reset()

        onStatus?("Capturing the virtual display...")
        try await capture.start(displayID: created.displayID, width: width, height: height, framesPerSecond: 6, showsCursor: locked { showsCursor }) { [weak self] bgra, w, h, stride in
            self?.handleFrame(bgra, w, h, stride)
        }
        onStatus?("Running: drag windows to the right edge of your main display")
    }

    private func handleFrame(_ bgra: UnsafePointer<UInt8>, _ width: Int, _ height: Int, _ stride: Int) {
        lock.lock()
        let tiles = differ.process(bgra: bgra, width: width, height: height, bytesPerRow: stride)
        lock.unlock()
        var bytes = 0
        for tile in tiles {
            server.sendTile(x: tile.x, y: tile.y, width: tile.width, height: tile.height, png: tile.png)
            bytes += tile.png.count
        }
        lock.lock(); tileCount += tiles.count; byteCount += bytes; lock.unlock()
    }

    private func resend() {
        lock.lock(); differ.reset(); lock.unlock()
    }

    // MARK: Page messages

    private func handleHello(_ info: DisplayClientInfo) {
        lock.lock()
        latest = info
        let isRunning = running
        let changed = info.width != size.width || info.height != size.height
        lock.unlock()
        guard isRunning else { return }
        if changed {
            restartTask?.cancel()
            restartTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(800))
                guard let self, !Task.isCancelled else { return }
                await self.restart(width: info.width, height: info.height)
            }
        } else {
            resend()
        }
    }

    private func restart(width: Int, height: Int) async {
        onStatus?("Boox screen changed, rebuilding the display...")
        await capture.stop()
        display?.destroy()
        display = nil
        do {
            try await startPipeline(width: width, height: height)
        } catch {
            onStatus?("Failed: \(error.localizedDescription)")
        }
    }

    private func waitForHello(after previous: DisplayClientInfo?, timeout: Double) async throws -> DisplayClientInfo {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let current = locked { latest }
            if let current, current != previous { return current }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw SecondDisplayError.browserNeverConnected
    }

    private func reportStats() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(1))
            let stats = locked { () -> Stats in
                let value = Stats(width: size.width, height: size.height, tilesPerSecond: tileCount, kilobytesPerSecond: byteCount / 1024)
                tileCount = 0
                byteCount = 0
                return value
            }
            onStats?(stats)
        }
    }
}
