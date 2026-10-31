import SwiftUI
import AppKit
import BooxSyncCore

/// Data and settings behind the dashboard shown on the Boox display.
@MainActor
final class DashboardModel: ObservableObject {
    private static func stored(_ key: String, default value: Bool = true) -> Bool {
        UserDefaults.standard.object(forKey: key) as? Bool ?? value
    }

    @Published var showClock = DashboardModel.stored("dashboard.clock") { didSet { UserDefaults.standard.set(showClock, forKey: "dashboard.clock") } }
    @Published var showCalendar = DashboardModel.stored("dashboard.calendar") { didSet { UserDefaults.standard.set(showCalendar, forKey: "dashboard.calendar") } }
    @Published var showNowPlaying = DashboardModel.stored("dashboard.nowPlaying") { didSet { UserDefaults.standard.set(showNowPlaying, forKey: "dashboard.nowPlaying") } }
    @Published var showResources = DashboardModel.stored("dashboard.resources") { didSet { UserDefaults.standard.set(showResources, forKey: "dashboard.resources") } }

    @Published private(set) var resources = ResourceSnapshot()
    @Published private(set) var cpuHistory: [Double] = []
    @Published private(set) var nowPlaying: NowPlayingStatus = .noPlayer
    @Published private(set) var artwork: NSImage?
    @Published private(set) var booxBattery: Int?

    private let monitor = SystemMonitor()
    private let provider = NowPlayingProvider()
    private var tasks: [Task<Void, Never>] = []
    private var artworkURL: URL?

    var anyWidgetOn: Bool { showClock || showCalendar || showNowPlaying || showResources }

    func start(fs: BooxFS?) {
        guard tasks.isEmpty else { return }
        // Slow on purpose: every change is a redraw on an e-ink panel.
        tasks.append(Task { [weak self] in
            while !Task.isCancelled {
                self?.sampleResources()
                try? await Task.sleep(for: .seconds(5))
            }
        })
        tasks.append(Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshNowPlaying()
                try? await Task.sleep(for: .seconds(4))
            }
        })
        if let fs {
            tasks.append(Task { [weak self] in
                while !Task.isCancelled {
                    let level = await fs.batteryLevel()
                    self?.booxBattery = level
                    try? await Task.sleep(for: .seconds(60))
                }
            })
        }
    }

    func stop() {
        tasks.forEach { $0.cancel() }
        tasks = []
    }

    private func sampleResources() {
        guard showResources else { return }
        let snapshot = monitor.sample()
        resources = snapshot
        cpuHistory.append(snapshot.cpu)
        if cpuHistory.count > 60 { cpuHistory.removeFirst(cpuHistory.count - 60) }
    }

    private func refreshNowPlaying() async {
        guard showNowPlaying else { return }
        let status = provider.current()
        if status != nowPlaying { nowPlaying = status }
        guard case .playing(let track) = status, let url = track.artworkURL else {
            if artworkURL != nil { artworkURL = nil; artwork = nil }
            return
        }
        guard url != artworkURL else { return }
        artworkURL = url
        if let (data, _) = try? await URLSession.shared.data(from: url), let image = NSImage(data: data) { artwork = image }
    }

    /// Fixed data so the layout can be rendered without any permissions (`BooxSync --render-dashboard out.png`).
    static func sample() -> DashboardModel {
        let model = DashboardModel()
        model.showClock = true; model.showCalendar = true; model.showNowPlaying = true; model.showResources = true
        var snapshot = ResourceSnapshot()
        snapshot.cpu = 0.37
        snapshot.memoryUsed = 25 << 30; snapshot.memoryTotal = 32 << 30
        snapshot.diskUsed = 358 << 30; snapshot.diskTotal = 926 << 30
        snapshot.networkDown = 1_250_000; snapshot.networkUp = 84_000
        snapshot.batteryPercent = 87; snapshot.batteryCharging = true
        model.resources = snapshot
        model.cpuHistory = (0..<60).map { (index: Int) -> Double in
            let x = Double(index)
            let slow = 0.2 * sin(x / 5)
            let fast = 0.1 * cos(x / 2)
            return 0.25 + slow + fast
        }
        model.booxBattery = 64
        model.nowPlaying = .playing(NowPlaying(
            source: "Spotify", title: "We Are The People", artist: "Empire Of The Sun", album: "Walking On A Dream",
            isPlaying: true, position: 83, duration: 233, artworkURL: nil))
        return model
    }
}
