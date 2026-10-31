import SwiftUI
import AppKit
import BooxSyncCore

@MainActor
final class DisplayModel: ObservableObject {
    enum Phase: Equatable {
        case idle
        case starting
        case running
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var status = "Not running"
    @Published private(set) var stats = SecondDisplaySession.Stats()

    /// Windows that are on the virtual (Boox) display, and everything else that can be sent there.
    @Published private(set) var windowsOnBoox: [WindowInfo] = []
    @Published private(set) var windowsOnMac: [WindowInfo] = []
    @Published private(set) var accessibilityTrusted = WindowMover.isTrusted(prompt: false)
    @Published var windowError: String?

    /// Draw the Mac pointer into the Boox picture. Handy now and then, hard to aim on e-ink.
    @AppStorage("display.showsCursor") var showsCursor = true {
        didSet { Task { await session?.setShowsCursor(showsCursor) } }
    }

    private let fs: BooxFS
    private var session: SecondDisplaySession?
    private var windowTask: Task<Void, Never>?
    /// Where a window was before it was sent, so "pull back" can put it there again.
    private var originalFrames: [CGWindowID: CGRect] = [:]

    init(fs: BooxFS) {
        self.fs = fs
    }

    var isActive: Bool { phase == .starting || phase == .running }

    func start() {
        guard !isActive else { return }
        phase = .starting
        status = "Starting..."
        stats = SecondDisplaySession.Stats()
        let session = SecondDisplaySession(fs: fs)
        Task { await session.setShowsCursor(showsCursor) }
        session.onStatus = { [weak self] text in
            Task { @MainActor in
                guard let self else { return }
                self.status = text
                if text.hasPrefix("Running") {
                    self.phase = .running
                    self.startWindowRefresh()
                }
            }
        }
        session.onStats = { [weak self] stats in
            Task { @MainActor in self?.stats = stats }
        }
        self.session = session
        Task {
            do {
                try await session.start()
            } catch {
                self.session = nil
                self.phase = .failed(error.localizedDescription)
                self.status = "Stopped"
            }
        }
    }

    func stop() {
        guard let session else { return }
        self.session = nil
        phase = .idle
        status = "Stopping..."
        Task {
            // Bring everything back first; windows left on a display that vanishes can end up off screen.
            await self.pullBackAll(displayID: session.virtualDisplayID)
            self.stopWindowRefresh()
            await session.stop()
            self.status = "Not running"
        }
    }

    // MARK: Windows

    private func startWindowRefresh() {
        guard windowTask == nil else { return }
        windowTask = Task {
            while !Task.isCancelled {
                refreshWindows()
                try? await Task.sleep(for: .seconds(1.5))
            }
        }
    }

    private func stopWindowRefresh() {
        windowTask?.cancel()
        windowTask = nil
        windowsOnBoox = []
        windowsOnMac = []
    }

    func refreshWindows() {
        accessibilityTrusted = WindowMover.isTrusted(prompt: false)
        let all = WindowMover.listWindows()
        guard let id = session?.virtualDisplayID else {
            windowsOnMac = all
            windowsOnBoox = []
            return
        }
        let boox = CGDisplayBounds(id)
        let onBoox = all.filter { boox.contains(CGPoint(x: $0.bounds.midX, y: $0.bounds.midY)) }
        let onBooxIDs = Set(onBoox.map(\.id))
        windowsOnBoox = onBoox
        windowsOnMac = all.filter { !onBooxIDs.contains($0.id) }
        originalFrames = originalFrames.filter { onBooxIDs.contains($0.key) }
    }

    func requestAccessibility() {
        accessibilityTrusted = WindowMover.isTrusted(prompt: true)
    }

    func openAccessibilitySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    func sendToBoox(_ window: WindowInfo) {
        guard let displayID = session?.virtualDisplayID else { return }
        guard WindowMover.isTrusted(prompt: true) else {
            accessibilityTrusted = false
            windowError = WindowMoveError.notTrusted.localizedDescription
            return
        }
        originalFrames[window.id] = window.bounds
        let target = WindowMover.usableFrame(of: displayID)
        move(window, to: target)
    }

    /// Puts one of the windows on the Boox above the others (they overlap because each fills the display).
    func bringToTop(_ window: WindowInfo) {
        Task {
            let error: String? = await Task.detached {
                do { try WindowMover.raise(window); return nil } catch { return error.localizedDescription }
            }.value
            if let error { windowError = error }
            // Raising needed the other app in front; hand focus back to BooxSync so the main screen stays in charge.
            try? await Task.sleep(for: .milliseconds(250))
            NSApp.activate(ignoringOtherApps: true)
            refreshWindows()
        }
    }

    func pullBack(_ window: WindowInfo) {
        move(window, to: pullBackTarget(for: window))
        originalFrames[window.id] = nil
    }

    private func pullBackTarget(for window: WindowInfo) -> CGRect {
        if let original = originalFrames[window.id], isOnActiveDisplay(original) { return original }
        return WindowMover.fallbackFrame(for: window)
    }

    private func isOnActiveDisplay(_ frame: CGRect) -> Bool {
        var count: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &count)
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetActiveDisplayList(count, &ids, &count)
        let center = CGPoint(x: frame.midX, y: frame.midY)
        return ids.contains { CGDisplayBounds($0).contains(center) && $0 != session?.virtualDisplayID }
    }

    func pullBackAll() {
        Task { await pullBackAll(displayID: session?.virtualDisplayID) }
    }

    private func pullBackAll(displayID: CGDirectDisplayID?) async {
        for window in windowsOnBoox {
            let target = pullBackTarget(for: window)
            await moveAsync(window, to: target)
            originalFrames[window.id] = nil
        }
        refreshWindows()
    }

    private func move(_ window: WindowInfo, to frame: CGRect) {
        Task {
            await moveAsync(window, to: frame)
            refreshWindows()
        }
    }

    /// Accessibility calls can block for seconds when an app is hung, so they run off the main actor.
    private func moveAsync(_ window: WindowInfo, to frame: CGRect) async {
        let error: String? = await Task.detached {
            do { try WindowMover.move(window, to: frame); return nil } catch { return error.localizedDescription }
        }.value
        if let error { windowError = error }
    }

    func openDisplaySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Displays-Settings.extension")!)
    }

    func openScreenRecordingSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
    }
}
