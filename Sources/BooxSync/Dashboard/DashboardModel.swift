import SwiftUI
import AppKit
import BooxSyncCore

struct TodoItem: Codable, Identifiable, Equatable {
    var id = UUID()
    var title: String
    var done = false
}

enum TodoSource: String, Codable { case local, reminders }

enum WeatherState: Equatable {
    case needsPlace
    case loading
    case ready(WeatherReport)
    case failed(String)
}

enum ReminderState: Equatable {
    case idle
    case denied
    case items([ReminderItem])
}

/// Layout, settings and live data behind the dashboard shown on the Boox display.
@MainActor
final class DashboardModel: ObservableObject {
    // MARK: Persistence

    private static let defaults = UserDefaults.standard

    private static func load<T: Decodable>(_ key: String, as type: T.Type) -> T? {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(type, from: $0) }
    }

    private static func save<T: Encodable>(_ value: T, key: String) {
        if let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: key) }
    }

    // MARK: Settings

    @Published var layout: DashboardLayout = DashboardModel.load("dashboard.layout.v1", as: DashboardLayout.self) ?? .standard {
        didSet { Self.save(layout, key: "dashboard.layout.v1") }
    }

    @Published var place: WeatherPlace? = DashboardModel.load("dashboard.place", as: WeatherPlace.self) {
        didSet {
            Self.save(place, key: "dashboard.place")
            Task { await refreshWeather(force: true) }
        }
    }

    @Published var fahrenheit: Bool = DashboardModel.defaults.object(forKey: "dashboard.fahrenheit") as? Bool
        ?? (Locale.current.measurementSystem == .us) {
        didSet {
            Self.defaults.set(fahrenheit, forKey: "dashboard.fahrenheit")
            Task { await refreshWeather(force: true) }
        }
    }

    @Published var todos: [TodoItem] = DashboardModel.load("dashboard.todos", as: [TodoItem].self) ?? [] {
        didSet { Self.save(todos, key: "dashboard.todos") }
    }

    @Published var todoSource: TodoSource = DashboardModel.load("dashboard.todoSource", as: TodoSource.self) ?? .local {
        didSet {
            Self.save(todoSource, key: "dashboard.todoSource")
            Task { await refreshReminders() }
        }
    }

    /// Empty means all lists.
    @Published var reminderList: String = DashboardModel.defaults.string(forKey: "dashboard.reminderList") ?? "" {
        didSet {
            Self.defaults.set(reminderList, forKey: "dashboard.reminderList")
            Task { await refreshReminders() }
        }
    }

    // MARK: Live data

    @Published private(set) var resources = ResourceSnapshot()
    @Published private(set) var cpuHistory: [Double] = []
    @Published private(set) var networkHistory: [Double] = []   // download bytes per second
    @Published private(set) var nowPlaying: NowPlayingStatus = .noPlayer
    @Published private(set) var artwork: NSImage?
    @Published private(set) var booxBattery: Int?
    @Published private(set) var weather: WeatherState = .needsPlace
    @Published private(set) var reminders: ReminderState = .idle
    @Published private(set) var reminderLists: [String] = []

    private let monitor = SystemMonitor()
    private let player = NowPlayingProvider()
    private let remindersProvider = RemindersProvider()
    private var tasks: [Task<Void, Never>] = []
    private var consumers = 0
    private var fs: BooxFS?
    private var artworkURL: URL?
    private var lastWeatherFetch: Date?

    private var needsResources: Bool { !layout.kinds().isDisjoint(with: [.cpu, .memory, .disk, .network, .battery]) }

    // MARK: Lifecycle

    /// The editor and the Boox window both show the dashboard; data loops run while at least one does.
    func retain(fs: BooxFS?) {
        consumers += 1
        if let fs { self.fs = fs }
        guard tasks.isEmpty else { return }
        // Slow on purpose: every change is a redraw on an e-ink panel.
        tasks.append(loop(every: 5) { [weak self] in self?.sampleResources() })
        tasks.append(loop(every: 4) { [weak self] in await self?.refreshNowPlaying() })
        tasks.append(loop(every: 60) { [weak self] in await self?.refreshBoxBattery() })
        tasks.append(loop(every: 60) { [weak self] in
            await self?.refreshWeather(force: false)
            await self?.refreshReminders()
        })
    }

    func release() {
        consumers = max(0, consumers - 1)
        guard consumers == 0 else { return }
        tasks.forEach { $0.cancel() }
        tasks = []
    }

    private func loop(every seconds: Double, _ body: @escaping @MainActor () async -> Void) -> Task<Void, Never> {
        Task {
            while !Task.isCancelled {
                await body()
                try? await Task.sleep(for: .seconds(seconds))
            }
        }
    }

    // MARK: Refreshers

    private func sampleResources() {
        guard needsResources else { return }
        let snapshot = monitor.sample()
        resources = snapshot
        cpuHistory.append(snapshot.cpu)
        if cpuHistory.count > 60 { cpuHistory.removeFirst(cpuHistory.count - 60) }
        networkHistory.append(snapshot.networkDown)
        if networkHistory.count > 60 { networkHistory.removeFirst(networkHistory.count - 60) }
    }

    private func refreshBoxBattery() async {
        guard layout.kinds().contains(.battery), let fs else { return }
        booxBattery = await fs.batteryLevel()
    }

    private func refreshNowPlaying() async {
        guard layout.kinds().contains(.nowPlaying) else { return }
        let status = player.current()
        if status != nowPlaying { nowPlaying = status }
        guard case .playing(let track) = status, let url = track.artworkURL else {
            if artworkURL != nil { artworkURL = nil; artwork = nil }
            return
        }
        guard url != artworkURL else { return }
        artworkURL = url
        if let (data, _) = try? await URLSession.shared.data(from: url), let image = NSImage(data: data) { artwork = image }
    }

    /// Weather changes slowly: at most every 30 minutes unless the place or units changed.
    func refreshWeather(force: Bool) async {
        guard layout.kinds().contains(.weather) else { return }
        if place == nil { place = await WeatherService.guessPlace(); return }   // setting `place` triggers a forced refresh
        guard let place else { weather = .needsPlace; return }
        if !force, let last = lastWeatherFetch, Date().timeIntervalSince(last) < 1800 { return }
        if case .ready = weather {} else { weather = .loading }
        do {
            weather = .ready(try await WeatherService.forecast(for: place, fahrenheit: fahrenheit))
            lastWeatherFetch = Date()
        } catch {
            if case .ready = weather { return }   // keep the last good report
            weather = .failed(error.localizedDescription)
        }
    }

    func refreshReminders() async {
        guard layout.kinds().contains(.todo), todoSource == .reminders else { return }
        switch await remindersProvider.fetch(list: reminderList.isEmpty ? nil : reminderList) {
        case .items(let items): reminders = .items(items)
        case .denied: reminders = .denied
        case .failed: break
        }
        if reminderLists.isEmpty { reminderLists = await remindersProvider.listNames() }
    }

    func searchPlaces(_ query: String) async -> [WeatherPlace] {
        (try? await WeatherService.search(query)) ?? []
    }

    // MARK: To-do editing (local list)

    func addTodo(_ title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        todos.append(TodoItem(title: trimmed))
    }

    func toggleTodo(_ id: UUID) {
        guard let index = todos.firstIndex(where: { $0.id == id }) else { return }
        todos[index].done.toggle()
    }

    func removeTodo(_ id: UUID) {
        todos.removeAll { $0.id == id }
    }

    // MARK: Editing helpers

    func applyPreset(_ index: Int) {
        guard DashboardLayout.presets.indices.contains(index) else { return }
        let outlines = layout.outlines
        layout = DashboardLayout.presets[index].layout
        layout.outlines = outlines
    }

    func setNote(_ id: UUID, text: String) {
        guard let index = layout.items.firstIndex(where: { $0.id == id }) else { return }
        layout.items[index].text = text
    }

    /// Fixed data so the layout can be rendered without permissions or network (`BooxSync --render-dashboard out.png`).
    static func sample() -> DashboardModel {
        let model = DashboardModel()
        model.layout = .standard
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
        model.networkHistory = (0..<60).map { (index: Int) -> Double in
            let x = Double(index)
            return 400_000 + 300_000 * sin(x / 4) + 200_000 * cos(x / 1.5)
        }
        model.booxBattery = 64
        model.nowPlaying = .playing(NowPlaying(
            source: "Spotify", title: "We Are The People", artist: "Empire Of The Sun", album: "Walking On A Dream",
            isPlaying: true, position: 83, duration: 233, artworkURL: nil))
        model.todos = [
            TodoItem(title: "Reply to the visa email"), TodoItem(title: "Book flights for December"),
            TodoItem(title: "Finish BooxSync dashboard"), TodoItem(title: "Buy paper refills"),
            TodoItem(title: "Review IELTS writing task 2", done: true),
        ]
        let place = WeatherPlace(name: "Hanoi", admin: "Hanoi", country: "Vietnam", latitude: 21.03, longitude: 105.85)
        let start = Calendar.current.startOfDay(for: Date())
        let days = (0..<5).map { (offset: Int) -> DailyForecast in
            DailyForecast(date: Calendar.current.date(byAdding: .day, value: offset, to: start)!,
                          code: [3, 61, 80, 2, 0][offset], high: 31 - Double(offset), low: 24 - Double(offset) / 2, rainChance: [10, 70, 60, 20, 0][offset])
        }
        model.weather = .ready(WeatherReport(place: place, temperature: 29.6, feelsLike: 33.1, humidity: 64, windKph: 9.4, code: 3,
                                             isDay: true, sunrise: "06:01", sunset: "17:25", daily: days, fetched: Date()))
        return model
    }
}
