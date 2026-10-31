import SwiftUI
import BooxSyncCore

/// One component. Every widget sizes its type from the box it is given, so any grid size works,
/// and each has a few variants (see `WidgetKind.variantNames`).
struct WidgetView: View {
    let item: WidgetItem
    @ObservedObject var model: DashboardModel
    let outlines: Bool
    let size: CGSize

    var body: some View {
        let v = item.safeVariant
        switch item.kind {
        case .clock: ClockWidget(size: size, outlines: outlines, variant: v)
        case .date: DateWidget(size: size, outlines: outlines, variant: v)
        case .calendar: CalendarWidget(size: size, outlines: outlines, variant: v)
        case .weather: WeatherWidget(model: model, size: size, outlines: outlines, variant: v)
        case .todo: TodoWidget(model: model, size: size, outlines: outlines, variant: v)
        case .nowPlaying: NowPlayingWidget(model: model, size: size, outlines: outlines, variant: v)
        case .cpu: CPUWidget(model: model, size: size, outlines: outlines, variant: v)
        case .memory: StatWidget(title: "Memory", fraction: model.resources.memoryFraction,
                                 detail: "\(Fmt.gigabytes(model.resources.memoryUsed)) of \(Fmt.gigabytes(model.resources.memoryTotal))",
                                 size: size, outlines: outlines, variant: v)
        case .disk: StatWidget(title: "Disk", fraction: model.resources.diskFraction,
                               detail: "\(Fmt.gigabytes(model.resources.diskUsed)) of \(Fmt.gigabytes(model.resources.diskTotal))",
                               size: size, outlines: outlines, variant: v)
        case .network: NetworkWidget(model: model, size: size, outlines: outlines, variant: v)
        case .battery: BatteryWidget(model: model, size: size, outlines: outlines, variant: v)
        case .note: NoteWidget(text: item.text, size: size, outlines: outlines, variant: v)
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
    @Environment(\.dashTheme) private var theme
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
        .foregroundStyle(theme.fg)
        .overlay {
            if outlines { RoundedRectangle(cornerRadius: 20 * u).stroke(theme.fg, lineWidth: max(2, 3 * u)) }
        }
    }
}

private func inset(_ u: CGFloat, _ outlines: Bool) -> CGFloat { (outlines ? 22 : 6) * u }

private struct Bar: View {
    @Environment(\.dashTheme) private var theme
    let fraction: Double
    let u: CGFloat

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 8 * u).stroke(theme.fg, lineWidth: max(2, 3 * u))
                RoundedRectangle(cornerRadius: 5 * u).fill(theme.fg)
                    .frame(width: max(0, (geo.size.width - 10 * u) * min(1, max(0, fraction))))
                    .padding(5 * u)
            }
        }
        .frame(height: 26 * u)
    }
}

private struct Sparkline: View {
    @Environment(\.dashTheme) private var theme
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
            context.stroke(path, with: .color(theme.fg), style: StrokeStyle(lineWidth: max(2, 3 * u), lineJoin: .round))
        }
        .overlay(alignment: .bottom) { Rectangle().fill(theme.fg).frame(height: max(1.5, 2 * u)) }
    }
}

/// A thick ring with the value in the middle, for the "Ring" variants.
private struct RingGauge: View {
    @Environment(\.dashTheme) private var theme
    let fraction: Double
    let diameter: CGFloat
    let text: String

    var body: some View {
        let line = diameter * 0.11
        ZStack {
            Circle().stroke(theme.fg.opacity(0.14), lineWidth: line)
            Circle().trim(from: 0, to: min(1, max(0.005, fraction)))
                .stroke(theme.fg, style: StrokeStyle(lineWidth: line, lineCap: .butt))
                .rotationEffect(.degrees(-90))
            Text(text).font(.system(size: diameter * 0.26, weight: .heavy)).monospacedDigit().minimumScaleFactor(0.5).lineLimit(1)
        }
        .padding(line / 2)
        .frame(width: diameter, height: diameter)
    }
}

// MARK: Clock

private struct ClockWidget: View {
    let size: CGSize
    let outlines: Bool
    let variant: Int

    var body: some View {
        let u = unit(size, reference: CGSize(width: 600, height: 300))
        TimelineView(.everyMinute) { context in
            Card(title: nil, u: u, outlines: outlines) {
                switch variant {
                case 1:
                    Text(context.date, format: .dateTime.hour().minute())
                        .font(.system(size: 230 * u, weight: .heavy)).monospacedDigit().minimumScaleFactor(0.2).lineLimit(1)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case 2: analog(context.date, u: u)
                case 3: digital(context.date, u: u, twelveHour: true)
                default: digital(context.date, u: u, twelveHour: false)
                }
            }
        }
    }

    private func digital(_ date: Date, u: CGFloat, twelveHour: Bool) -> some View {
        let showDate = size.height / size.width > 0.36
        return VStack(alignment: .leading, spacing: 0) {
            Group {
                if twelveHour {
                    Text(date.formatted(Date.FormatStyle().hour(.defaultDigits(amPM: .abbreviated)).minute().locale(Locale(identifier: "en_US"))))
                } else {
                    Text(date, format: .dateTime.hour().minute())
                }
            }
            .font(.system(size: 135 * u, weight: .heavy)).monospacedDigit().minimumScaleFactor(0.3).lineLimit(1)
            if showDate {
                Text(date.formatted(.dateTime.weekday(.wide))).font(.system(size: 40 * u, weight: .bold)).lineLimit(1)
                Text(date.formatted(date: .long, time: .omitted)).font(.system(size: 28 * u, weight: .medium)).lineLimit(1)
            }
        }
    }

    private func analog(_ date: Date, u: CGFloat) -> some View {
        let pad = inset(u, outlines)
        let diameter = max(40, min(size.height - 2 * pad, size.width - 2 * pad))
        let wide = size.width > size.height * 1.5
        return HStack(spacing: 28 * u) {
            AnalogFace(date: date).frame(width: diameter, height: diameter)
            if wide {
                VStack(alignment: .leading, spacing: 4 * u) {
                    Text(date.formatted(.dateTime.weekday(.wide))).font(.system(size: 46 * u, weight: .bold)).lineLimit(1)
                    Text(date.formatted(.dateTime.day().month(.wide))).font(.system(size: 36 * u, weight: .medium)).lineLimit(1)
                    Text(date.formatted(.dateTime.year())).font(.system(size: 28 * u)).lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: wide ? .leading : .center)
    }
}

private struct AnalogFace: View {
    @Environment(\.dashTheme) private var theme
    let date: Date

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = min(size.width, size.height) / 2 - 4
            let weight = max(3, radius * 0.03)
            context.stroke(Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)),
                           with: .color(theme.fg), lineWidth: weight)
            func point(_ angle: Double, _ length: CGFloat) -> CGPoint {
                CGPoint(x: center.x + CoreGraphics.sin(angle) * length, y: center.y - CoreGraphics.cos(angle) * length)
            }
            for tick in 0..<12 {
                let angle = Double(tick) / 12 * 2 * .pi
                var path = Path()
                path.move(to: point(angle, radius * (tick % 3 == 0 ? 0.80 : 0.88)))
                path.addLine(to: point(angle, radius * 0.95))
                context.stroke(path, with: .color(theme.fg), style: StrokeStyle(lineWidth: tick % 3 == 0 ? weight * 2 : weight, lineCap: .round))
            }
            let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
            let minutes = Double(parts.minute ?? 0)
            let hours = Double((parts.hour ?? 0) % 12) + minutes / 60
            for (angle, length, width) in [(hours / 12 * 2 * .pi, 0.50, weight * 3.2), (minutes / 60 * 2 * .pi, 0.76, weight * 2.2)] {
                var hand = Path()
                hand.move(to: center)
                hand.addLine(to: point(angle, radius * length))
                context.stroke(hand, with: .color(theme.fg), style: StrokeStyle(lineWidth: width, lineCap: .round))
            }
            context.fill(Path(ellipseIn: CGRect(x: center.x - weight * 2.2, y: center.y - weight * 2.2, width: weight * 4.4, height: weight * 4.4)), with: .color(theme.fg))
        }
    }
}

// MARK: Date

private struct DateWidget: View {
    let size: CGSize
    let outlines: Bool
    let variant: Int

    var body: some View {
        TimelineView(.everyMinute) { context in
            switch variant {
            case 1: oneLine(context.date)
            case 2: weekAndDay(context.date)
            default: bigDay(context.date)
            }
        }
    }

    private func bigDay(_ date: Date) -> some View {
        let u = unit(size, reference: CGSize(width: 360, height: 360))
        return Card(title: nil, u: u, outlines: outlines) {
            VStack(alignment: .leading, spacing: 0) {
                Text(date.formatted(.dateTime.weekday(.wide))).font(.system(size: 38 * u, weight: .bold)).lineLimit(1)
                Text(date.formatted(.dateTime.day()))
                    .font(.system(size: 190 * u, weight: .heavy)).monospacedDigit().minimumScaleFactor(0.3).lineLimit(1)
                Text(date.formatted(.dateTime.month(.wide).year())).font(.system(size: 32 * u, weight: .medium)).lineLimit(1)
            }
        }
    }

    private func oneLine(_ date: Date) -> some View {
        let u = unit(size, reference: CGSize(width: 560, height: 150))
        return Card(title: nil, u: u, outlines: outlines) {
            Text(date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).year()))
                .font(.system(size: 58 * u, weight: .heavy)).minimumScaleFactor(0.3).lineLimit(1)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }

    private func weekAndDay(_ date: Date) -> some View {
        let u = unit(size, reference: CGSize(width: 420, height: 300))
        let calendar = Calendar.current
        let week = calendar.component(.weekOfYear, from: date)
        let day = calendar.ordinality(of: .day, in: .year, for: date) ?? 1
        let total = calendar.range(of: .day, in: .year, for: date)?.count ?? 365
        return Card(title: "Week", u: u, outlines: outlines) {
            Text("\(week)").font(.system(size: 120 * u, weight: .heavy)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.4)
            Text("Day \(day) of \(total)").font(.system(size: 26 * u, weight: .semibold)).lineLimit(1)
            Bar(fraction: Double(day) / Double(total), u: u)
        }
    }
}

// MARK: Calendar

private struct DayCell: View {
    @Environment(\.dashTheme) private var theme
    let day: Date
    let today: Date
    let cell: CGFloat
    let calendar: Calendar

    var body: some View {
        let isToday = calendar.isDate(day, inSameDayAs: today)
        Text("\(calendar.component(.day, from: day))")
            .font(.system(size: cell * 0.5, weight: isToday ? .heavy : .medium))
            .foregroundStyle(isToday ? theme.bg : theme.fg)
            .frame(width: cell * 0.86, height: cell * 0.86)
            .background(Circle().fill(isToday ? theme.fg : Color.clear))
            .frame(width: cell, height: cell)
    }
}

private struct CalendarWidget: View {
    let size: CGSize
    let outlines: Bool
    let variant: Int

    var body: some View {
        TimelineView(.everyMinute) { context in
            switch variant {
            case 1: weekStrip(context.date)
            case 2: twoWeeks(context.date)
            default: month(context.date)
            }
        }
    }

    private func month(_ date: Date) -> some View {
        let u = unit(size, reference: CGSize(width: 540, height: 520))
        let pad = inset(u, outlines)
        let cell = max(18, min((size.width - 2 * pad) / 7, (size.height - 2 * pad - 36 * u * 1.4 - 28 * u) / 6))
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: date)
        let days = Self.cells(for: date, calendar: calendar)
        let symbols = Self.weekdayHeaders(calendar)
        return Card(title: nil, u: u, outlines: outlines) {
            Text(date.formatted(.dateTime.month(.wide).year())).font(.system(size: 36 * u, weight: .bold)).lineLimit(1)
            dayGrid(symbols: symbols, days: days, today: today, cell: cell, u: u, calendar: calendar)
        }
    }

    /// Weekday header plus rows of seven days. Plain stacks, not a lazy grid, so every row always renders.
    private func dayGrid(symbols: [String], days: [Date?], today: Date, cell: CGFloat, u: CGFloat, calendar: Calendar) -> some View {
        let rows = stride(from: 0, to: days.count, by: 7).map { Array(days[$0..<min($0 + 7, days.count)]) }
        return VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(0..<7, id: \.self) { index in
                    Text(symbols[index]).font(.system(size: min(22 * u, cell * 0.45), weight: .bold)).frame(width: cell, height: 28 * u)
                }
            }
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 0) {
                    ForEach(0..<7, id: \.self) { column in
                        if column < row.count, let day = row[column] {
                            DayCell(day: day, today: today, cell: cell, calendar: calendar)
                        } else {
                            Color.clear.frame(width: cell, height: cell)
                        }
                    }
                }
            }
        }
    }

    private func weekStrip(_ date: Date) -> some View {
        let u = unit(size, reference: CGSize(width: 600, height: 240))
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: date)
        let start = calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? today
        let cell = max(24, min((size.width - 2 * inset(u, outlines)) / 7, size.height * 0.45))
        return Card(title: nil, u: u, outlines: outlines) {
            Text(date.formatted(.dateTime.month(.wide).year())).font(.system(size: 30 * u, weight: .bold)).lineLimit(1)
            HStack(spacing: 0) {
                ForEach(0..<7, id: \.self) { offset in
                    let day = calendar.date(byAdding: .day, value: offset, to: start) ?? start
                    VStack(spacing: 4 * u) {
                        Text(day.formatted(.dateTime.weekday(.abbreviated))).font(.system(size: 22 * u, weight: .bold))
                        DayCell(day: day, today: today, cell: cell, calendar: calendar)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(maxHeight: .infinity)
        }
    }

    private func twoWeeks(_ date: Date) -> some View {
        let u = unit(size, reference: CGSize(width: 540, height: 340))
        let pad = inset(u, outlines)
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: date)
        let start = calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? today
        let cell = max(18, min((size.width - 2 * pad) / 7, (size.height - 2 * pad - 36 * u * 1.4 - 28 * u) / 2))
        let symbols = Self.weekdayHeaders(calendar)
        return Card(title: nil, u: u, outlines: outlines) {
            Text(date.formatted(.dateTime.month(.wide).year())).font(.system(size: 34 * u, weight: .bold)).lineLimit(1)
            dayGrid(symbols: symbols, days: (0..<14).map { calendar.date(byAdding: .day, value: $0, to: start) }, today: today, cell: cell, u: u, calendar: calendar)
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
    @Environment(\.dashTheme) private var theme
    @ObservedObject var model: DashboardModel
    let size: CGSize
    let outlines: Bool
    let variant: Int

    private var reference: CGSize {
        switch variant {
        case 1: CGSize(width: 520, height: 300)
        case 3: CGSize(width: 440, height: 130)
        default: CGSize(width: 1000, height: 300)
        }
    }

    var body: some View {
        let u = unit(size, reference: reference)
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

    @ViewBuilder
    private func content(_ report: WeatherReport, u: CGFloat) -> some View {
        let now = WeatherService.describe(code: report.code, isDay: report.isDay)
        switch variant {
        case 1: currentOnly(report, now: now, u: u)
        case 2: forecastOnly(report, u: u)
        case 3: compact(report, now: now, u: u)
        default: full(report, now: now, u: u)
        }
    }

    private func details(_ report: WeatherReport, u: CGFloat, scale: CGFloat = 1) -> some View {
        VStack(alignment: .leading, spacing: 2 * u) {
            Text("Feels \(Fmt.temperature(report.feelsLike)) · \(report.humidity)% · \(Int(report.windKph.rounded())) km/h")
                .font(.system(size: 21 * u * scale)).lineLimit(1).minimumScaleFactor(0.6)
            if let rise = report.sunrise, let set = report.sunset {
                Text("↑ \(rise)  ↓ \(set)   \(model.fahrenheit ? "°F" : "°C")").font(.system(size: 20 * u * scale)).lineLimit(1)
            }
        }
    }

    private func dayColumn(_ day: DailyForecast, u: CGFloat, scale: CGFloat) -> some View {
        VStack(spacing: 4 * u) {
            Text(day.date.formatted(.dateTime.weekday(.abbreviated))).font(.system(size: 22 * u * scale, weight: .bold))
            Image(systemName: WeatherService.describe(code: day.code).symbol).font(.system(size: 40 * u * scale))
            Text(Fmt.temperature(day.high)).font(.system(size: 26 * u * scale, weight: .heavy)).monospacedDigit()
            Text(Fmt.temperature(day.low)).font(.system(size: 22 * u * scale)).monospacedDigit()
            if let rain = day.rainChance { Text("\(rain)%").font(.system(size: 18 * u * scale, weight: .semibold)) }
        }
        .frame(maxWidth: .infinity)
    }

    private func full(_ report: WeatherReport, now: (text: String, symbol: String), u: CGFloat) -> some View {
        let dayCount = max(0, min(report.daily.count, Int(size.width * 0.58 / (118 * u))))
        return Card(title: "Weather · \(report.place.name)", u: u, outlines: outlines) {
            HStack(alignment: .center, spacing: 24 * u) {
                HStack(spacing: 16 * u) {
                    Image(systemName: now.symbol).font(.system(size: 80 * u))
                    VStack(alignment: .leading, spacing: 2 * u) {
                        Text(Fmt.temperature(report.temperature)).font(.system(size: 92 * u, weight: .heavy)).monospacedDigit().lineLimit(1)
                        Text(now.text).font(.system(size: 28 * u, weight: .bold)).lineLimit(1)
                        details(report, u: u)
                    }
                }
                if dayCount > 0 {
                    Rectangle().fill(theme.fg).frame(width: max(2, 2 * u))
                    HStack(spacing: 0) {
                        ForEach(Array(report.daily.prefix(dayCount).enumerated()), id: \.offset) { _, day in dayColumn(day, u: u, scale: 1) }
                    }
                }
            }
            .frame(maxHeight: .infinity)
        }
    }

    private func currentOnly(_ report: WeatherReport, now: (text: String, symbol: String), u: CGFloat) -> some View {
        Card(title: "Weather · \(report.place.name)", u: u, outlines: outlines) {
            HStack(spacing: 24 * u) {
                Image(systemName: now.symbol).font(.system(size: 120 * u))
                VStack(alignment: .leading, spacing: 4 * u) {
                    Text(Fmt.temperature(report.temperature)).font(.system(size: 130 * u, weight: .heavy)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.4)
                    Text(now.text).font(.system(size: 38 * u, weight: .bold)).lineLimit(1)
                    details(report, u: u, scale: 1.2)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func forecastOnly(_ report: WeatherReport, u: CGFloat) -> some View {
        let count = max(1, min(report.daily.count, Int((size.width - 2 * inset(u, outlines)) / (130 * u))))
        return Card(title: "Forecast · \(report.place.name)", u: u, outlines: outlines) {
            HStack(spacing: 0) {
                ForEach(Array(report.daily.prefix(count).enumerated()), id: \.offset) { _, day in dayColumn(day, u: u, scale: 1.3) }
            }
            .frame(maxHeight: .infinity)
        }
    }

    private func compact(_ report: WeatherReport, now: (text: String, symbol: String), u: CGFloat) -> some View {
        Card(title: nil, u: u, outlines: outlines) {
            HStack(spacing: 14 * u) {
                Image(systemName: now.symbol).font(.system(size: 52 * u))
                Text(Fmt.temperature(report.temperature)).font(.system(size: 64 * u, weight: .heavy)).monospacedDigit()
                VStack(alignment: .leading, spacing: 0) {
                    Text(now.text).font(.system(size: 26 * u, weight: .bold)).lineLimit(1)
                    Text(report.place.name).font(.system(size: 20 * u)).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }
}

// MARK: To-do

private struct TodoWidget: View {
    @ObservedObject var model: DashboardModel
    let size: CGSize
    let outlines: Bool
    let variant: Int

    private struct Row: Identifiable { let id: String; let title: String; let done: Bool; let due: Date? }

    private var rows: [Row] {
        switch model.todoSource {
        case .local:
            let open = model.todos.filter { !$0.done }, done = model.todos.filter(\.done)
            // The focus variant only shows what is still open.
            return (variant == 2 ? open : open + done).map { Row(id: $0.id.uuidString, title: $0.title, done: $0.done, due: nil) }
        case .reminders:
            if case .items(let items) = model.reminders { return items.map { Row(id: $0.id, title: $0.title, done: false, due: $0.due) } }
            return []
        }
    }

    var body: some View {
        let u = unit(size, reference: CGSize(width: 520, height: 560))
        // font, row height, checkbox size, maximum rows
        let style: (font: CGFloat, pitch: CGFloat, box: CGFloat, limit: Int) = switch variant {
        case 1: (21, 33, 21, 99)
        case 2: (44, 70, 40, 4)
        default: (28, 46, 28, 99)
        }
        let all = rows
        let capacity = min(style.limit, max(1, Int((size.height - 2 * inset(u, outlines) - 40 * u) / (style.pitch * u))))
        let shown = Array(all.prefix(all.count > capacity ? capacity - 1 : capacity))
        let hidden = all.count - shown.count
        Card(title: "To-do", u: u, outlines: outlines) {
            if model.todoSource == .reminders, model.reminders == .denied {
                Text("Allow Reminders access for BooxSync").font(.system(size: 26 * u, weight: .bold))
                Text("System Settings > Privacy & Security > Reminders.").font(.system(size: 20 * u))
            } else if all.isEmpty {
                Text(model.todoSource == .local ? "Nothing to do" : "No open reminders").font(.system(size: 28 * u, weight: .semibold))
            } else {
                VStack(alignment: .leading, spacing: (style.pitch - style.font * 1.2) * u) {
                    ForEach(shown) { row in
                        HStack(spacing: 12 * u) {
                            Image(systemName: row.done ? "checkmark.square.fill" : "square").font(.system(size: style.box * u))
                            Text(row.title).font(.system(size: style.font * u, weight: variant == 2 ? .bold : .medium))
                                .strikethrough(row.done).lineLimit(1).minimumScaleFactor(0.6)
                            Spacer(minLength: 4 * u)
                            if let due = row.due {
                                Text(due.formatted(.dateTime.day().month(.abbreviated)))
                                    .font(.system(size: max(14, style.font * 0.68) * u, weight: due < Date() ? .heavy : .regular))
                            }
                        }
                    }
                    if hidden > 0 { Text("+ \(hidden) more").font(.system(size: 22 * u, weight: .semibold)) }
                }
            }
        }
    }
}

// MARK: Now playing

private struct NowPlayingWidget: View {
    @Environment(\.dashTheme) private var theme
    @ObservedObject var model: DashboardModel
    let size: CGSize
    let outlines: Bool
    let variant: Int

    var body: some View {
        let u = unit(size, reference: CGSize(width: 760, height: 300))
        Card(title: "Now playing", u: u, outlines: outlines) {
            switch model.nowPlaying {
            case .playing(let track):
                switch variant {
                case 1: artOnly(track, u: u)
                case 2: textOnly(track, u: u)
                default: full(track, u: u)
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

    private func progress(_ track: NowPlaying, u: CGFloat) -> some View {
        VStack(spacing: 4 * u) {
            Bar(fraction: track.duration > 0 ? track.position / track.duration : 0, u: u)
            HStack {
                Text(track.isPlaying ? "Playing" : "Paused").font(.system(size: 20 * u, weight: .bold))
                Text("· \(track.source)").font(.system(size: 20 * u))
                Spacer()
                Text("\(Fmt.time(track.position)) / \(Fmt.time(track.duration))").font(.system(size: 20 * u, weight: .medium)).monospacedDigit()
            }
        }
    }

    private func full(_ track: NowPlaying, u: CGFloat) -> some View {
        let art = max(60, min(size.height - 100 * u, size.width * 0.34))
        return HStack(alignment: .top, spacing: 20 * u) {
            artwork(u: u).frame(width: art, height: art)
            VStack(alignment: .leading, spacing: 4 * u) {
                Text(track.title).font(.system(size: 38 * u, weight: .heavy)).lineLimit(2).minimumScaleFactor(0.6)
                Text(track.artist).font(.system(size: 27 * u, weight: .semibold)).lineLimit(1)
                Text(track.album).font(.system(size: 21 * u)).lineLimit(1)
                Spacer(minLength: 4 * u)
                progress(track, u: u)
            }
        }
    }

    private func artOnly(_ track: NowPlaying, u: CGFloat) -> some View {
        let art = max(60, min(size.width - 2 * inset(u, outlines), size.height - 2 * inset(u, outlines) - 110 * u))
        return VStack(spacing: 8 * u) {
            artwork(u: u).frame(width: art, height: art)
            Text(track.title).font(.system(size: 30 * u, weight: .heavy)).lineLimit(1).minimumScaleFactor(0.5)
            Text(track.artist).font(.system(size: 22 * u, weight: .semibold)).lineLimit(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func textOnly(_ track: NowPlaying, u: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 6 * u) {
            Text(track.title).font(.system(size: 54 * u, weight: .heavy)).lineLimit(3).minimumScaleFactor(0.5)
            Text(track.artist).font(.system(size: 36 * u, weight: .semibold)).lineLimit(1)
            Text(track.album).font(.system(size: 26 * u)).lineLimit(1)
            Spacer(minLength: 4 * u)
            progress(track, u: u)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func artwork(u: CGFloat) -> some View {
        if let image = model.artwork {
            Image(nsImage: image).resizable().interpolation(.high).aspectRatio(contentMode: .fill)
                .grayscale(1).contrast(1.2)
                .clipShape(RoundedRectangle(cornerRadius: 10 * u))
                .overlay(RoundedRectangle(cornerRadius: 10 * u).stroke(theme.fg, lineWidth: max(2, 3 * u)))
        } else {
            RoundedRectangle(cornerRadius: 10 * u).stroke(theme.fg, lineWidth: max(2, 3 * u))
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
    let variant: Int

    var body: some View {
        let u = unit(size, reference: CGSize(width: 420, height: 300))
        let cpu = model.resources.cpu
        Card(title: "CPU", u: u, outlines: outlines) {
            switch variant {
            case 1:
                ring(cpu, "\(Int(cpu * 100))%", u: u)
            case 2:
                Text("\(Int(cpu * 100))%").font(.system(size: 170 * u, weight: .heavy)).monospacedDigit()
                    .minimumScaleFactor(0.3).lineLimit(1).frame(maxWidth: .infinity, maxHeight: .infinity)
            default:
                Text("\(Int(cpu * 100))%").font(.system(size: 64 * u, weight: .heavy)).monospacedDigit()
                Bar(fraction: cpu, u: u)
                if size.height / u > 240 { Sparkline(values: model.cpuHistory, u: u).frame(maxHeight: .infinity) }
            }
        }
    }

    private func ring(_ fraction: Double, _ text: String, u: CGFloat) -> some View {
        let diameter = max(50, min(size.width - 2 * inset(u, outlines), size.height - 2 * inset(u, outlines) - 30 * u))
        return RingGauge(fraction: fraction, diameter: diameter, text: text).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct StatWidget: View {
    let title: String
    let fraction: Double
    let detail: String
    let size: CGSize
    let outlines: Bool
    let variant: Int

    var body: some View {
        let u = unit(size, reference: CGSize(width: 420, height: 200))
        let percent = "\(Int(fraction * 100))%"
        Card(title: title, u: u, outlines: outlines) {
            switch variant {
            case 1:
                let diameter = max(50, min(size.width - 2 * inset(u, outlines), size.height - 2 * inset(u, outlines) - 70 * u))
                VStack(spacing: 4 * u) {
                    RingGauge(fraction: fraction, diameter: diameter, text: percent)
                    Text(detail).font(.system(size: 22 * u, weight: .medium)).lineLimit(1).minimumScaleFactor(0.6)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case 2:
                VStack(spacing: 0) {
                    Text(percent).font(.system(size: 150 * u, weight: .heavy)).monospacedDigit().minimumScaleFactor(0.3).lineLimit(1)
                    Text(detail).font(.system(size: 26 * u, weight: .medium)).lineLimit(1).minimumScaleFactor(0.6)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            default:
                HStack(alignment: .firstTextBaseline) {
                    Text(percent).font(.system(size: 54 * u, weight: .heavy)).monospacedDigit()
                    Spacer()
                    Text(detail).font(.system(size: 22 * u, weight: .medium)).lineLimit(1).minimumScaleFactor(0.6)
                }
                Bar(fraction: fraction, u: u)
            }
        }
    }
}

private struct NetworkWidget: View {
    @ObservedObject var model: DashboardModel
    let size: CGSize
    let outlines: Bool
    let variant: Int

    var body: some View {
        let u = unit(size, reference: CGSize(width: 420, height: 200))
        let r = model.resources
        Card(title: "Network", u: u, outlines: outlines) {
            switch variant {
            case 1:
                Text("↓ \(Fmt.rate(r.networkDown))   ↑ \(Fmt.rate(r.networkUp))")
                    .font(.system(size: 28 * u, weight: .heavy)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.5)
                let peak = max(1000, model.networkHistory.max() ?? 1000)
                Sparkline(values: model.networkHistory.map { $0 / peak }, u: u).frame(maxHeight: .infinity)
            case 2:
                Text("↓ \(Fmt.rate(r.networkDown))   ↑ \(Fmt.rate(r.networkUp))")
                    .font(.system(size: 34 * u, weight: .heavy)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.4)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            default:
                Text("↓ \(Fmt.rate(r.networkDown))").font(.system(size: 40 * u, weight: .heavy)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.5)
                Text("↑ \(Fmt.rate(r.networkUp))").font(.system(size: 40 * u, weight: .semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.5)
            }
        }
    }
}

private struct BatteryWidget: View {
    @ObservedObject var model: DashboardModel
    let size: CGSize
    let outlines: Bool
    let variant: Int

    private var entries: [(label: String, percent: Int, suffix: String)] {
        var list: [(String, Int, String)] = []
        if let mac = model.resources.batteryPercent { list.append(("Mac", mac, model.resources.batteryCharging ? " ⚡︎" : "")) }
        if let boox = model.booxBattery { list.append(("Boox", boox, "")) }
        return list
    }

    var body: some View {
        let u = unit(size, reference: CGSize(width: 420, height: 200))
        Card(title: "Battery", u: u, outlines: outlines) {
            if entries.isEmpty {
                Text("No battery data").font(.system(size: 24 * u))
            } else {
                switch variant {
                case 1:
                    let diameter = max(50, min((size.width - 2 * inset(u, outlines)) / CGFloat(entries.count) - 12 * u,
                                               size.height - 2 * inset(u, outlines) - 60 * u))
                    HStack(spacing: 12 * u) {
                        ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
                            VStack(spacing: 2 * u) {
                                RingGauge(fraction: Double(entry.percent) / 100, diameter: diameter, text: "\(entry.percent)%")
                                Text(entry.label + entry.suffix).font(.system(size: 22 * u, weight: .bold))
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .frame(maxHeight: .infinity)
                case 2:
                    Text(entries.map { "\($0.label) \($0.percent)%\($0.suffix)" }.joined(separator: "  ·  "))
                        .font(.system(size: 34 * u, weight: .heavy)).lineLimit(1).minimumScaleFactor(0.4)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                default:
                    ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
                        VStack(alignment: .leading, spacing: 4 * u) {
                            HStack {
                                Text(entry.label).font(.system(size: 24 * u, weight: .bold))
                                Spacer()
                                Text("\(entry.percent)%\(entry.suffix)").font(.system(size: 24 * u, weight: .medium)).monospacedDigit()
                            }
                            Bar(fraction: Double(entry.percent) / 100, u: u)
                        }
                    }
                }
            }
        }
    }
}

// MARK: Note

private struct NoteWidget: View {
    let text: String
    let size: CGSize
    let outlines: Bool
    let variant: Int

    var body: some View {
        let u = unit(size, reference: CGSize(width: 520, height: 300))
        let base: CGFloat = variant == 1 ? 62 : (variant == 2 ? 46 : 34)
        Card(title: nil, u: u, outlines: outlines) {
            Text(text.isEmpty ? "Empty note. Select it in the Dashboard tab to write something." : text)
                .font(.system(size: base * u, weight: text.isEmpty ? .regular : .semibold))
                .italic(variant == 2)
                .multilineTextAlignment(variant == 2 ? .center : .leading)
                .lineLimit(nil).minimumScaleFactor(0.3)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: variant == 2 ? .center : .topLeading)
        }
    }
}
