import SwiftUI
import BooxSyncCore

/// Designed for e-ink: black on white, thick outlines, large type, no animation, minute-level updates.
struct DashboardView: View {
    @ObservedObject var model: DashboardModel
    /// Height of the menu bar that macOS draws over the top of the display.
    var topInset: CGFloat = 0

    private let referenceHeight: CGFloat = 1302

    var body: some View {
        GeometryReader { geo in
            let s = max(0.4, geo.size.height / referenceHeight)
            let hasLeft = model.showClock || model.showCalendar
            let hasRight = model.showNowPlaying || model.showResources
            ZStack {
                Color.white
                if !model.anyWidgetOn {
                    Text("No widgets selected").font(.system(size: 48 * s, weight: .semibold)).foregroundStyle(.black)
                } else {
                    HStack(spacing: 24 * s) {
                        if hasLeft {
                            VStack(spacing: 24 * s) {
                                if model.showClock { ClockWidget(s: s) }
                                if model.showCalendar { CalendarWidget(s: s) }
                            }
                            .frame(width: hasRight ? (geo.size.width - 24 * s - 64 * s) * 0.40 : nil)
                        }
                        if hasRight {
                            VStack(spacing: 24 * s) {
                                if model.showNowPlaying { NowPlayingWidget(model: model, s: s) }
                                if model.showResources { ResourcesWidget(model: model, s: s) }
                            }
                        }
                    }
                    .padding(.top, topInset + 20 * s)
                    .padding(.horizontal, 32 * s)
                    .padding(.bottom, 32 * s)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .environment(\.colorScheme, .light)
    }
}

// MARK: Building blocks

private struct Card<Content: View>: View {
    let title: String?
    let s: CGFloat
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12 * s) {
            if let title {
                Text(title.uppercased())
                    .font(.system(size: 20 * s, weight: .bold))
                    .tracking(2 * s)
                    .foregroundStyle(Color.black)
            }
            content
        }
        .padding(26 * s)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .overlay(RoundedRectangle(cornerRadius: 22 * s).stroke(Color.black, lineWidth: 3 * s))
    }
}

private struct Bar: View {
    let fraction: Double
    let s: CGFloat

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 8 * s).stroke(Color.black, lineWidth: 3 * s)
                RoundedRectangle(cornerRadius: 5 * s)
                    .fill(Color.black)
                    .frame(width: max(0, (geo.size.width - 10 * s) * min(1, max(0, fraction))))
                    .padding(5 * s)
            }
        }
        .frame(height: 28 * s)
    }
}

// MARK: Clock

private struct ClockWidget: View {
    let s: CGFloat

    var body: some View {
        TimelineView(.everyMinute) { context in
            VStack(alignment: .leading, spacing: 0) {
                Text(context.date, format: .dateTime.hour().minute())
                    .font(.system(size: 210 * s, weight: .heavy))
                    .monospacedDigit()
                    .minimumScaleFactor(0.4).lineLimit(1)
                Text(context.date.formatted(.dateTime.weekday(.wide)))
                    .font(.system(size: 62 * s, weight: .bold))
                Text(context.date.formatted(date: .long, time: .omitted))
                    .font(.system(size: 40 * s, weight: .medium))
            }
            .foregroundStyle(Color.black)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 6 * s)
        }
        .frame(height: 360 * s)
    }
}

// MARK: Calendar

private struct CalendarWidget: View {
    let s: CGFloat

    var body: some View {
        TimelineView(.everyMinute) { context in
            let calendar = Calendar.current
            let today = calendar.startOfDay(for: context.date)
            let days = Self.cells(for: context.date, calendar: calendar)
            Card(title: nil, s: s) {
                Text(context.date.formatted(.dateTime.month(.wide).year()))
                    .font(.system(size: 44 * s, weight: .bold))
                let symbols = Self.weekdayHeaders(calendar)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 6 * s) {
                    ForEach(0..<7, id: \.self) { index in
                        Text(symbols[index]).font(.system(size: 24 * s, weight: .bold))
                    }
                    ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                        if let day {
                            let isToday = calendar.isDate(day, inSameDayAs: today)
                            Text("\(calendar.component(.day, from: day))")
                                .font(.system(size: 32 * s, weight: isToday ? .heavy : .medium))
                                .foregroundStyle(isToday ? Color.white : Color.black)
                                .frame(width: 52 * s, height: 52 * s)
                                .background(Circle().fill(isToday ? Color.black : Color.clear))
                        } else {
                            Color.clear.frame(height: 52 * s)
                        }
                    }
                }
                .foregroundStyle(Color.black)
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

// MARK: Now playing

private struct NowPlayingWidget: View {
    @ObservedObject var model: DashboardModel
    let s: CGFloat

    var body: some View {
        Card(title: "Now playing", s: s) {
            switch model.nowPlaying {
            case .playing(let track):
                HStack(alignment: .top, spacing: 26 * s) {
                    artwork.frame(width: 230 * s, height: 230 * s)
                    VStack(alignment: .leading, spacing: 8 * s) {
                        Text(track.title).font(.system(size: 50 * s, weight: .heavy)).lineLimit(2)
                        Text(track.artist).font(.system(size: 36 * s, weight: .semibold)).lineLimit(1)
                        Text(track.album).font(.system(size: 28 * s, weight: .regular)).lineLimit(1)
                        Spacer(minLength: 6 * s)
                        Bar(fraction: track.duration > 0 ? track.position / track.duration : 0, s: s)
                        HStack {
                            Text(track.isPlaying ? "Playing" : "Paused").font(.system(size: 24 * s, weight: .bold))
                            Text("· \(track.source)").font(.system(size: 24 * s))
                            Spacer()
                            Text("\(Self.time(track.position)) / \(Self.time(track.duration))")
                                .font(.system(size: 24 * s, weight: .medium)).monospacedDigit()
                        }
                    }
                }
            case .noPlayer:
                message("No music player running", detail: "Open Spotify or Music to see the track here.")
            case .idle:
                message("Nothing playing", detail: nil)
            case .automationDenied:
                message("Allow BooxSync to control your player", detail: "System Settings > Privacy & Security > Automation.")
            }
        }
        .foregroundStyle(Color.black)
    }

    @ViewBuilder
    private var artwork: some View {
        if let image = model.artwork {
            Image(nsImage: image).resizable().interpolation(.high).aspectRatio(contentMode: .fill)
                .grayscale(1).contrast(1.2)
                .clipShape(RoundedRectangle(cornerRadius: 12 * s))
                .overlay(RoundedRectangle(cornerRadius: 12 * s).stroke(Color.black, lineWidth: 3 * s))
        } else {
            RoundedRectangle(cornerRadius: 12 * s).stroke(Color.black, lineWidth: 3 * s)
                .overlay(Image(systemName: "music.note").font(.system(size: 90 * s)))
        }
    }

    private func message(_ text: String, detail: String?) -> some View {
        VStack(alignment: .leading, spacing: 8 * s) {
            Text(text).font(.system(size: 40 * s, weight: .bold))
            if let detail { Text(detail).font(.system(size: 26 * s)) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    static func time(_ seconds: Double) -> String {
        let total = Int(max(0, seconds))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

// MARK: Resources

private struct ResourcesWidget: View {
    @ObservedObject var model: DashboardModel
    let s: CGFloat

    var body: some View {
        let r = model.resources
        Card(title: "System", s: s) {
            VStack(alignment: .leading, spacing: 14 * s) {
                row("CPU", value: "\(Int(r.cpu * 100))%", fraction: r.cpu)
                Sparkline(values: model.cpuHistory, s: s).frame(height: 70 * s)
                row("Memory", value: "\(Self.gigabytes(r.memoryUsed)) / \(Self.gigabytes(r.memoryTotal))", fraction: r.memoryFraction)
                row("Disk", value: "\(Self.gigabytes(r.diskUsed)) / \(Self.gigabytes(r.diskTotal))", fraction: r.diskFraction)
                HStack {
                    Text("Network").font(.system(size: 28 * s, weight: .bold))
                    Spacer()
                    Text("↓ \(Self.rate(r.networkDown))   ↑ \(Self.rate(r.networkUp))")
                        .font(.system(size: 28 * s, weight: .medium)).monospacedDigit()
                }
                if let battery = r.batteryPercent {
                    row("Mac battery", value: "\(battery)%\(r.batteryCharging ? " ⚡︎" : "")", fraction: Double(battery) / 100)
                }
                if let boox = model.booxBattery {
                    row("Boox battery", value: "\(boox)%", fraction: Double(boox) / 100)
                }
            }
        }
        .foregroundStyle(Color.black)
    }

    private func row(_ label: String, value: String, fraction: Double) -> some View {
        VStack(alignment: .leading, spacing: 6 * s) {
            HStack {
                Text(label).font(.system(size: 28 * s, weight: .bold))
                Spacer()
                Text(value).font(.system(size: 28 * s, weight: .medium)).monospacedDigit()
            }
            Bar(fraction: fraction, s: s)
        }
    }

    static func gigabytes(_ bytes: UInt64) -> String {
        String(format: "%.1f GB", Double(bytes) / 1_073_741_824)
    }

    static func rate(_ bytesPerSecond: Double) -> String {
        if bytesPerSecond >= 1_000_000 { return String(format: "%.1f MB/s", bytesPerSecond / 1_000_000) }
        return String(format: "%.0f KB/s", bytesPerSecond / 1000)
    }
}

private struct Sparkline: View {
    let values: [Double]
    let s: CGFloat

    var body: some View {
        Canvas { context, size in
            guard values.count > 1 else { return }
            var path = Path()
            for (index, value) in values.enumerated() {
                let point = CGPoint(x: size.width * CGFloat(index) / CGFloat(values.count - 1),
                                    y: size.height * (1 - CGFloat(min(1, max(0, value)))))
                index == 0 ? path.move(to: point) : path.addLine(to: point)
            }
            context.stroke(path, with: .color(.black), style: StrokeStyle(lineWidth: 3 * s, lineJoin: .round))
        }
        .overlay(alignment: .bottom) { Rectangle().fill(Color.black).frame(height: 2 * s) }
    }
}
