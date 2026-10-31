import SwiftUI
import BooxSyncCore

/// One component. Every widget sizes its type from the box it is given, so any grid size works.
struct WidgetView: View {
    let item: WidgetItem
    @ObservedObject var model: DashboardModel
    let outlines: Bool
    let size: CGSize

    var body: some View {
        switch item.kind {
        case .clock: ClockWidget(size: size, outlines: outlines)
        case .date: DateWidget(size: size, outlines: outlines)
        case .calendar: CalendarWidget(size: size, outlines: outlines)
        case .weather: WeatherWidget(model: model, size: size, outlines: outlines)
        case .todo: TodoWidget(model: model, size: size, outlines: outlines)
        case .nowPlaying: NowPlayingWidget(model: model, size: size, outlines: outlines)
        case .cpu: CPUWidget(model: model, size: size, outlines: outlines)
        case .memory: StatWidget(title: "Memory", fraction: model.resources.memoryFraction,
                                 detail: "\(Fmt.gigabytes(model.resources.memoryUsed)) of \(Fmt.gigabytes(model.resources.memoryTotal))",
                                 size: size, outlines: outlines)
        case .disk: StatWidget(title: "Disk", fraction: model.resources.diskFraction,
                               detail: "\(Fmt.gigabytes(model.resources.diskUsed)) of \(Fmt.gigabytes(model.resources.diskTotal))",
                               size: size, outlines: outlines)
        case .network: NetworkWidget(model: model, size: size, outlines: outlines)
        case .battery: BatteryWidget(model: model, size: size, outlines: outlines)
        case .note: NoteWidget(text: item.text, size: size, outlines: outlines)
        }
    }
}

// MARK: Shared pieces

enum Fmt {
    static func gigabytes(_ bytes: UInt64) -> String { String(format: "%.1f GB", Double(bytes) / 1_073_741_824) }

    static func rate(_ bytesPerSecond: Double) -> String {
        bytesPerSecond >= 1_000_000 ? String(format: "%.1f MB/s", bytesPerSecond / 1_000_000) : String(format: "%.0f KB/s", bytesPerSecond / 1000)
    }

    static func temperature(_ value: Double) -> String { "\(Int(value.rounded()))°" }

    static func time(_ seconds: Double) -> String {
        let total = Int(max(0, seconds))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

/// Type scale for a widget: how much bigger or smaller than the reference size it is drawn.
private func unit(_ size: CGSize, reference: CGSize) -> CGFloat {
    max(0.3, min(size.width / reference.width, size.height / reference.height))
}

private struct Card<Content: View>: View {
    let title: String?
    let u: CGFloat
    let outlines: Bool
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8 * u) {
            if let title {
                Text(title.uppercased()).font(.system(size: 17 * u, weight: .bold)).tracking(1.5 * u).lineLimit(1)
            }
            content
        }
        .padding(outlines ? 22 * u : 6 * u)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .foregroundStyle(Color.black)
        .overlay {
            if outlines { RoundedRectangle(cornerRadius: 20 * u).stroke(Color.black, lineWidth: max(2, 3 * u)) }
        }
    }
}

private struct Bar: View {
    let fraction: Double
    let u: CGFloat

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 8 * u).stroke(Color.black, lineWidth: max(2, 3 * u))
                RoundedRectangle(cornerRadius: 5 * u).fill(Color.black)
                    .frame(width: max(0, (geo.size.width - 10 * u) * min(1, max(0, fraction))))
                    .padding(5 * u)
            }
        }
        .frame(height: 26 * u)
    }
}

private struct Sparkline: View {
    let values: [Double]
    let u: CGFloat

    var body: some View {
        Canvas { context, size in
            guard values.count > 1 else { return }
            var path = Path()
            for (index, value) in values.enumerated() {
                let point = CGPoint(x: size.width * CGFloat(index) / CGFloat(values.count - 1),
                                    y: size.height * (1 - CGFloat(min(1, max(0, value)))))
                index == 0 ? path.move(to: point) : path.addLine(to: point)
            }
            context.stroke(path, with: .color(.black), style: StrokeStyle(lineWidth: max(2, 3 * u), lineJoin: .round))
        }
        .overlay(alignment: .bottom) { Rectangle().fill(Color.black).frame(height: max(1.5, 2 * u)) }
    }
}

// MARK: Clock and date

private struct ClockWidget: View {
    let size: CGSize
    let outlines: Bool

    var body: some View {
        let u = unit(size, reference: CGSize(width: 600, height: 300))
        let showDate = size.height / size.width > 0.36
        TimelineView(.everyMinute) { context in
            Card(title: nil, u: u, outlines: outlines) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(context.date, format: .dateTime.hour().minute())
                        .font(.system(size: 135 * u, weight: .heavy)).monospacedDigit()
                        .minimumScaleFactor(0.3).lineLimit(1)
                    if showDate {
                        Text(context.date.formatted(.dateTime.weekday(.wide))).font(.system(size: 40 * u, weight: .bold)).lineLimit(1)
                        Text(context.date.formatted(date: .long, time: .omitted)).font(.system(size: 28 * u, weight: .medium)).lineLimit(1)
                    }
                }
            }
        }
    }
}

private struct DateWidget: View {
    let size: CGSize
    let outlines: Bool

    var body: some View {
        let u = unit(size, reference: CGSize(width: 360, height: 360))
        TimelineView(.everyMinute) { context in
            Card(title: nil, u: u, outlines: outlines) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(context.date.formatted(.dateTime.weekday(.wide))).font(.system(size: 38 * u, weight: .bold)).lineLimit(1)
                    Text(context.date.formatted(.dateTime.day()))
                        .font(.system(size: 190 * u, weight: .heavy)).monospacedDigit().minimumScaleFactor(0.3).lineLimit(1)
                    Text(context.date.formatted(.dateTime.month(.wide).year())).font(.system(size: 32 * u, weight: .medium)).lineLimit(1)
                }
            }
        }
    }
}

// MARK: Calendar

private struct CalendarWidget: View {
    let size: CGSize
    let outlines: Bool

    var body: some View {
        let u = unit(size, reference: CGSize(width: 540, height: 520))
        let pad = (outlines ? 22 : 6) * u
        let cell = max(18, min((size.width - 2 * pad) / 7, (size.height - 2 * pad - 36 * u * 1.4 - 28 * u) / 6))
        TimelineView(.everyMinute) { context in
            let calendar = Calendar.current
            let today = calendar.startOfDay(for: context.date)
            let days = Self.cells(for: context.date, calendar: calendar)
            let symbols = Self.weekdayHeaders(calendar)
            Card(title: nil, u: u, outlines: outlines) {
                Text(context.date.formatted(.dateTime.month(.wide).year())).font(.system(size: 36 * u, weight: .bold)).lineLimit(1)
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(cell), spacing: 0), count: 7), spacing: 0) {
                    ForEach(0..<7, id: \.self) { index in
                        Text(symbols[index]).font(.system(size: min(22 * u, cell * 0.45), weight: .bold)).frame(height: 28 * u)
                    }
                    ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                        if let day {
                            let isToday = calendar.isDate(day, inSameDayAs: today)
                            Text("\(calendar.component(.day, from: day))")
                                .font(.system(size: cell * 0.5, weight: isToday ? .heavy : .medium))
                                .foregroundStyle(isToday ? Color.white : Color.black)
                                .frame(width: cell * 0.86, height: cell * 0.86)
                                .background(Circle().fill(isToday ? Color.black : Color.clear))
                                .frame(width: cell, height: cell)
                        } else {
                            Color.clear.frame(width: cell, height: cell)
                        }
                    }
                }
            }
        }
    }

    static func weekdayHeaders(_ calendar: Calendar) -> [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    /// Leading blanks for the weekday the month starts on, then one entry per day.
    static func cells(for date: Date, calendar: Calendar) -> [Date?] {
        guard let month = calendar.dateInterval(of: .month, for: date),
              let days = calendar.range(of: .day, in: .month, for: date) else { return [] }
        let weekday = calendar.component(.weekday, from: month.start)
        let leading = (weekday - calendar.firstWeekday + 7) % 7
        var cells: [Date?] = Array(repeating: nil, count: leading)
        for offset in 0..<days.count { cells.append(calendar.date(byAdding: .day, value: offset, to: month.start)) }
        return cells
    }
}

// MARK: Weather

private struct WeatherWidget: View {
    @ObservedObject var model: DashboardModel
    let size: CGSize
    let outlines: Bool

    var body: some View {
        let u = unit(size, reference: CGSize(width: 1000, height: 300))
        switch model.weather {
        case .ready(let current): content(current, u: u)
        case .loading:
            Card(title: "Weather", u: u, outlines: outlines) { Text("Loading...").font(.system(size: 36 * u, weight: .semibold)) }
        case .needsPlace:
            Card(title: "Weather", u: u, outlines: outlines) {
                Text("Choose a city").font(.system(size: 36 * u, weight: .bold))
                Text("Select this widget in the Dashboard tab.").font(.system(size: 24 * u))
            }
        case .failed(let message):
            Card(title: "Weather", u: u, outlines: outlines) {
                Text("Weather unavailable").font(.system(size: 36 * u, weight: .bold))
                Text(message).font(.system(size: 22 * u)).lineLimit(2)
            }
        }
    }

    private func content(_ report: WeatherReport, u: CGFloat) -> some View {
        let now = WeatherService.describe(code: report.code, isDay: report.isDay)
        let unitLabel = model.fahrenheit ? "°F" : "°C"
        let forecastWidth = size.width * 0.58
        let dayWidth = 118 * u
        let dayCount = max(0, min(report.daily.count, Int(forecastWidth / dayWidth)))
        return Card(title: "Weather · \(report.place.name)", u: u, outlines: outlines) {
            HStack(alignment: .center, spacing: 24 * u) {
                HStack(spacing: 16 * u) {
                    Image(systemName: now.symbol).font(.system(size: 80 * u))
                    VStack(alignment: .leading, spacing: 2 * u) {
                        Text(Fmt.temperature(report.temperature)).font(.system(size: 92 * u, weight: .heavy)).monospacedDigit().lineLimit(1)
                        Text(now.text).font(.system(size: 28 * u, weight: .bold)).lineLimit(1)
                        Text("Feels \(Fmt.temperature(report.feelsLike)) · \(report.humidity)% · \(Int(report.windKph.rounded())) km/h")
                            .font(.system(size: 21 * u)).lineLimit(1).minimumScaleFactor(0.6)
                        if let rise = report.sunrise, let set = report.sunset {
                            Text("↑ \(rise)  ↓ \(set)   \(unitLabel)").font(.system(size: 20 * u)).lineLimit(1)
                        }
                    }
                }
                if dayCount > 0 {
                    Rectangle().fill(Color.black).frame(width: max(2, 2 * u))
                    HStack(spacing: 0) {
                        ForEach(Array(report.daily.prefix(dayCount).enumerated()), id: \.offset) { _, day in
                            VStack(spacing: 4 * u) {
                                Text(day.date.formatted(.dateTime.weekday(.abbreviated))).font(.system(size: 22 * u, weight: .bold))
                                Image(systemName: WeatherService.describe(code: day.code).symbol).font(.system(size: 40 * u))
                                Text(Fmt.temperature(day.high)).font(.system(size: 26 * u, weight: .heavy)).monospacedDigit()
                                Text(Fmt.temperature(day.low)).font(.system(size: 22 * u)).monospacedDigit()
                                if let rain = day.rainChance { Text("\(rain)%").font(.system(size: 18 * u, weight: .semibold)) }
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
            .frame(maxHeight: .infinity)
        }
    }
}

// MARK: To-do

private struct TodoWidget: View {
    @ObservedObject var model: DashboardModel
    let size: CGSize
    let outlines: Bool

    private struct Row: Identifiable { let id: String; let title: String; let done: Bool; let due: Date? }

    private var rows: [Row] {
        switch model.todoSource {
        case .local:
            let open = model.todos.filter { !$0.done }, done = model.todos.filter(\.done)
            return (open + done).map { Row(id: $0.id.uuidString, title: $0.title, done: $0.done, due: nil) }
        case .reminders:
            if case .items(let items) = model.reminders { return items.map { Row(id: $0.id, title: $0.title, done: false, due: $0.due) } }
            return []
        }
    }

    var body: some View {
        let u = unit(size, reference: CGSize(width: 520, height: 560))
        let all = rows
        let pad = (outlines ? 22 : 6) * u
        let capacity = max(1, Int((size.height - 2 * pad - 40 * u) / (46 * u)))
        let shown = Array(all.prefix(all.count > capacity ? capacity - 1 : capacity))
        let hidden = all.count - shown.count
        Card(title: "To-do", u: u, outlines: outlines) {
            if model.todoSource == .reminders, model.reminders == .denied {
                Text("Allow Reminders access for BooxSync").font(.system(size: 26 * u, weight: .bold))
                Text("System Settings > Privacy & Security > Reminders.").font(.system(size: 20 * u))
            } else if all.isEmpty {
                Text(model.todoSource == .local ? "Nothing to do" : "No open reminders").font(.system(size: 28 * u, weight: .semibold))
            } else {
                VStack(alignment: .leading, spacing: 8 * u) {
                    ForEach(shown) { row in
                        HStack(spacing: 12 * u) {
                            Image(systemName: row.done ? "checkmark.square.fill" : "square").font(.system(size: 28 * u))
                            Text(row.title).font(.system(size: 28 * u, weight: .medium)).strikethrough(row.done).lineLimit(1)
                            Spacer(minLength: 4 * u)
                            if let due = row.due {
                                Text(due.formatted(.dateTime.day().month(.abbreviated))).font(.system(size: 19 * u, weight: due < Date() ? .heavy : .regular))
                            }
                        }
                        .frame(height: 38 * u)
                    }
                    if hidden > 0 { Text("+ \(hidden) more").font(.system(size: 22 * u, weight: .semibold)) }
                }
            }
        }
    }
}

// MARK: Now playing

private struct NowPlayingWidget: View {
    @ObservedObject var model: DashboardModel
    let size: CGSize
    let outlines: Bool

    var body: some View {
        let u = unit(size, reference: CGSize(width: 760, height: 300))
        Card(title: "Now playing", u: u, outlines: outlines) {
            switch model.nowPlaying {
            case .playing(let track):
                let art = min(size.height - 100 * u, size.width * 0.34)
                HStack(alignment: .top, spacing: 20 * u) {
                    artwork(u: u).frame(width: art, height: art)
                    VStack(alignment: .leading, spacing: 4 * u) {
                        Text(track.title).font(.system(size: 38 * u, weight: .heavy)).lineLimit(2).minimumScaleFactor(0.6)
                        Text(track.artist).font(.system(size: 27 * u, weight: .semibold)).lineLimit(1)
                        Text(track.album).font(.system(size: 21 * u)).lineLimit(1)
                        Spacer(minLength: 4 * u)
                        Bar(fraction: track.duration > 0 ? track.position / track.duration : 0, u: u)
                        HStack {
                            Text(track.isPlaying ? "Playing" : "Paused").font(.system(size: 20 * u, weight: .bold))
                            Text("· \(track.source)").font(.system(size: 20 * u))
                            Spacer()
                            Text("\(Fmt.time(track.position)) / \(Fmt.time(track.duration))").font(.system(size: 20 * u, weight: .medium)).monospacedDigit()
                        }
                    }
                }
            case .noPlayer:
                message("No music player running", "Open Spotify or Music.", u: u)
            case .idle:
                message("Nothing playing", nil, u: u)
            case .automationDenied:
                message("Allow BooxSync to control your player", "System Settings > Privacy & Security > Automation.", u: u)
            }
        }
    }

    @ViewBuilder
    private func artwork(u: CGFloat) -> some View {
        if let image = model.artwork {
            Image(nsImage: image).resizable().interpolation(.high).aspectRatio(contentMode: .fill)
                .grayscale(1).contrast(1.2)
                .clipShape(RoundedRectangle(cornerRadius: 10 * u))
                .overlay(RoundedRectangle(cornerRadius: 10 * u).stroke(Color.black, lineWidth: max(2, 3 * u)))
        } else {
            RoundedRectangle(cornerRadius: 10 * u).stroke(Color.black, lineWidth: max(2, 3 * u))
                .overlay(Image(systemName: "music.note").font(.system(size: 70 * u)))
        }
    }

    private func message(_ text: String, _ detail: String?, u: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 6 * u) {
            Text(text).font(.system(size: 32 * u, weight: .bold))
            if let detail { Text(detail).font(.system(size: 22 * u)) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

// MARK: System

private struct CPUWidget: View {
    @ObservedObject var model: DashboardModel
    let size: CGSize
    let outlines: Bool

    var body: some View {
        let u = unit(size, reference: CGSize(width: 420, height: 300))
        let showHistory = size.height > 230 * u * 0.9 && size.height / u > 240
        Card(title: "CPU", u: u, outlines: outlines) {
            Text("\(Int(model.resources.cpu * 100))%").font(.system(size: 64 * u, weight: .heavy)).monospacedDigit()
            Bar(fraction: model.resources.cpu, u: u)
            if showHistory { Sparkline(values: model.cpuHistory, u: u).frame(maxHeight: .infinity) }
        }
    }
}

private struct StatWidget: View {
    let title: String
    let fraction: Double
    let detail: String
    let size: CGSize
    let outlines: Bool

    var body: some View {
        let u = unit(size, reference: CGSize(width: 420, height: 200))
        Card(title: title, u: u, outlines: outlines) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(Int(fraction * 100))%").font(.system(size: 54 * u, weight: .heavy)).monospacedDigit()
                Spacer()
                Text(detail).font(.system(size: 22 * u, weight: .medium)).lineLimit(1).minimumScaleFactor(0.6)
            }
            Bar(fraction: fraction, u: u)
        }
    }
}

private struct NetworkWidget: View {
    @ObservedObject var model: DashboardModel
    let size: CGSize
    let outlines: Bool

    var body: some View {
        let u = unit(size, reference: CGSize(width: 420, height: 200))
        Card(title: "Network", u: u, outlines: outlines) {
            Text("↓ \(Fmt.rate(model.resources.networkDown))").font(.system(size: 40 * u, weight: .heavy)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.5)
            Text("↑ \(Fmt.rate(model.resources.networkUp))").font(.system(size: 40 * u, weight: .semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.5)
        }
    }
}

private struct BatteryWidget: View {
    @ObservedObject var model: DashboardModel
    let size: CGSize
    let outlines: Bool

    var body: some View {
        let u = unit(size, reference: CGSize(width: 420, height: 200))
        Card(title: "Battery", u: u, outlines: outlines) {
            if let mac = model.resources.batteryPercent {
                row("Mac", value: "\(mac)%\(model.resources.batteryCharging ? " ⚡︎" : "")", fraction: Double(mac) / 100, u: u)
            }
            if let boox = model.booxBattery {
                row("Boox", value: "\(boox)%", fraction: Double(boox) / 100, u: u)
            }
            if model.resources.batteryPercent == nil, model.booxBattery == nil {
                Text("No battery data").font(.system(size: 24 * u))
            }
        }
    }

    private func row(_ label: String, value: String, fraction: Double, u: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 4 * u) {
            HStack {
                Text(label).font(.system(size: 24 * u, weight: .bold))
                Spacer()
                Text(value).font(.system(size: 24 * u, weight: .medium)).monospacedDigit()
            }
            Bar(fraction: fraction, u: u)
        }
    }
}

// MARK: Note

private struct NoteWidget: View {
    let text: String
    let size: CGSize
    let outlines: Bool

    var body: some View {
        let u = unit(size, reference: CGSize(width: 520, height: 300))
        Card(title: nil, u: u, outlines: outlines) {
            Text(text.isEmpty ? "Empty note. Select it in the Dashboard tab to write something." : text)
                .font(.system(size: 34 * u, weight: text.isEmpty ? .regular : .semibold))
                .lineLimit(nil).minimumScaleFactor(0.4)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}
