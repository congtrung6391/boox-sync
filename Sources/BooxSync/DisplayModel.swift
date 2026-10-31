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

    private let fs: BooxFS
    private var session: SecondDisplaySession?

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
        session.onStatus = { [weak self] text in
            Task { @MainActor in
                guard let self else { return }
                self.status = text
                if text.hasPrefix("Running") { self.phase = .running }
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
            await session.stop()
            self.status = "Not running"
        }
    }

    func openDisplaySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Displays-Settings.extension")!)
    }

    func openScreenRecordingSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
    }
}
