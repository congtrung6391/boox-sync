import Foundation

public enum WidgetKind: String, Codable, CaseIterable, Sendable {
    case clock, date, calendar, weather, todo, nowPlaying, cpu, memory, disk, network, battery, note

    public var title: String {
        switch self {
        case .clock: "Clock"
        case .date: "Date"
        case .calendar: "Calendar"
        case .weather: "Weather"
        case .todo: "To-do"
        case .nowPlaying: "Now playing"
        case .cpu: "CPU"
        case .memory: "Memory"
        case .disk: "Disk"
        case .network: "Network"
        case .battery: "Battery"
        case .note: "Note"
        }
    }

    /// Alternative looks for the component. The first one is the default.
    public var variantNames: [String] {
        switch self {
        case .clock: ["Digital", "Time only", "Analog", "12-hour"]
        case .date: ["Big day", "One line", "Week and day"]
        case .calendar: ["Month", "Week strip", "Two weeks"]
        case .weather: ["Current and forecast", "Current only", "Forecast only", "Compact"]
        case .todo: ["Checklist", "Compact", "Focus"]
        case .nowPlaying: ["Artwork and text", "Artwork only", "Text only"]
        case .cpu: ["Bar and history", "Ring", "Big number"]
        case .memory, .disk: ["Bar", "Ring", "Big number"]
        case .network: ["Rates", "Rates and graph", "Compact"]
        case .battery: ["Bars", "Rings", "Compact"]
        case .note: ["Normal", "Large", "Quote"]
        }
    }

    /// SF Symbol for the palette.
    public var symbol: String {
        switch self {
        case .clock: "clock"
        case .date: "calendar.badge.clock"
        case .calendar: "calendar"
        case .weather: "cloud.sun"
        case .todo: "checklist"
        case .nowPlaying: "music.note"
        case .cpu: "cpu"
        case .memory: "memorychip"
        case .disk: "internaldrive"
        case .network: "arrow.up.arrow.down"
        case .battery: "battery.75percent"
        case .note: "note.text"
        }
    }

    /// Size in grid cells when added, and the smallest size that still reads well.
    public var defaultSize: (cols: Int, rows: Int) {
        switch self {
        case .clock: (4, 2)
        case .date: (3, 3)
        case .calendar: (4, 5)
        case .weather: (8, 2)
        case .todo: (4, 4)
        case .nowPlaying: (4, 3)
        case .cpu: (3, 2)
        case .memory, .disk, .network, .battery: (3, 2)
        case .note: (4, 3)
        }
    }

    public var minSize: (cols: Int, rows: Int) {
        switch self {
        case .clock: (3, 2)
        case .date: (2, 2)
        case .calendar: (3, 4)
        case .weather: (4, 2)
        case .todo: (3, 2)
        case .nowPlaying: (4, 2)
        case .cpu: (2, 2)
        case .memory, .disk, .network, .battery: (2, 1)
        case .note: (2, 1)
        }
    }
}

public struct WidgetItem: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var kind: WidgetKind
    public var col: Int
    public var row: Int
    public var cols: Int
    public var rows: Int
    /// Used by the note widget.
    public var text = ""
    /// Index into `kind.variantNames`.
    public var variant = 0

    public init(kind: WidgetKind, col: Int, row: Int, cols: Int, rows: Int, text: String = "", variant: Int = 0) {
        self.kind = kind
        self.col = col
        self.row = row
        self.cols = cols
        self.rows = rows
        self.text = text
        self.variant = variant
    }

    // Layouts saved before variants existed have no "variant" key; they decode as variant 0.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        kind = try c.decode(WidgetKind.self, forKey: .kind)
        col = try c.decode(Int.self, forKey: .col)
        row = try c.decode(Int.self, forKey: .row)
        cols = try c.decode(Int.self, forKey: .cols)
        rows = try c.decode(Int.self, forKey: .rows)
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        variant = try c.decodeIfPresent(Int.self, forKey: .variant) ?? 0
    }

    /// The variant clamped to what the kind offers, so a stale value can never index out of range.
    public var safeVariant: Int { min(max(0, variant), kind.variantNames.count - 1) }
}

/// Widgets placed on a 12 x 8 grid that covers the Boox display. Edits that would overlap or leave the grid are refused.
public struct DashboardLayout: Codable, Equatable, Sendable {
    public static let columns = 12
    public static let rows = 8

    public var items: [WidgetItem]
    public var outlines = true

    public init(items: [WidgetItem], outlines: Bool = true) {
        self.items = items
        self.outlines = outlines
    }

    public func kinds() -> Set<WidgetKind> { Set(items.map(\.kind)) }

    public func inBounds(_ item: WidgetItem) -> Bool {
        item.col >= 0 && item.row >= 0 && item.cols >= item.kind.minSize.cols && item.rows >= item.kind.minSize.rows
            && item.col + item.cols <= Self.columns && item.row + item.rows <= Self.rows
    }

    public func overlaps(_ item: WidgetItem, ignoring id: UUID? = nil) -> Bool {
        items.contains { other in
            other.id != id && other.id != item.id
                && item.col < other.col + other.cols && other.col < item.col + item.cols
                && item.row < other.row + other.rows && other.row < item.row + item.rows
        }
    }

    public func isFree(_ item: WidgetItem) -> Bool { inBounds(item) && !overlaps(item) }

    /// Puts a new widget in the first free spot (row by row), shrinking towards its minimum size if needed.
    @discardableResult
    public mutating func add(_ kind: WidgetKind) -> UUID? {
        var size = kind.defaultSize
        while true {
            for row in 0...(Self.rows - size.rows) {
                for col in 0...(Self.columns - size.cols) {
                    let candidate = WidgetItem(kind: kind, col: col, row: row, cols: size.cols, rows: size.rows)
                    if isFree(candidate) {
                        items.append(candidate)
                        return candidate.id
                    }
                }
            }
            if size.cols > kind.minSize.cols { size.cols -= 1 }
            else if size.rows > kind.minSize.rows { size.rows -= 1 }
            else { return nil }
        }
    }

    @discardableResult
    public mutating func move(_ id: UUID, toCol col: Int, row: Int) -> Bool {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return false }
        var moved = items[index]
        moved.col = col
        moved.row = row
        guard isFree(moved) else { return false }
        items[index] = moved
        return true
    }

    @discardableResult
    public mutating func resize(_ id: UUID, cols: Int, rows: Int) -> Bool {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return false }
        var resized = items[index]
        resized.cols = cols
        resized.rows = rows
        guard isFree(resized) else { return false }
        items[index] = resized
        return true
    }

    public mutating func setVariant(_ id: UUID, _ variant: Int) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].variant = min(max(0, variant), items[index].kind.variantNames.count - 1)
    }

    public mutating func remove(_ id: UUID) {
        items.removeAll { $0.id == id }
    }

    // MARK: Presets

    public static let presets: [(name: String, layout: DashboardLayout)] = [
        ("Desk", make([
            (.clock, 0, 0, 4, 2, 0), (.calendar, 0, 2, 4, 6, 0), (.weather, 4, 0, 8, 2, 0),
            (.todo, 4, 2, 4, 4, 0), (.nowPlaying, 8, 2, 4, 4, 0),
            (.cpu, 4, 6, 3, 2, 0), (.memory, 7, 6, 3, 2, 0), (.battery, 10, 6, 2, 2, 0),
        ])),
        ("Calm", make([
            (.date, 0, 0, 4, 4, 0), (.clock, 4, 0, 8, 4, 1), (.calendar, 0, 4, 5, 4, 0), (.weather, 5, 4, 7, 4, 0),
        ])),
        ("Focus", make([
            (.todo, 0, 0, 6, 8, 0), (.clock, 6, 0, 6, 2, 3), (.weather, 6, 2, 6, 2, 3), (.calendar, 6, 4, 6, 4, 2),
        ])),
        ("Music", make([
            (.nowPlaying, 0, 0, 12, 5, 0), (.clock, 0, 5, 4, 3, 0), (.weather, 4, 5, 8, 3, 0),
        ])),
        ("Monitor", make([
            (.cpu, 0, 0, 6, 3, 0), (.memory, 6, 0, 3, 3, 1), (.disk, 9, 0, 3, 3, 1), (.network, 0, 3, 6, 2, 1),
            (.battery, 6, 3, 6, 2, 0), (.clock, 0, 5, 4, 3, 0), (.weather, 4, 5, 8, 3, 0),
        ])),
        ("Clock only", make([(.clock, 0, 0, 12, 8, 0)])),
        ("Analog", make([(.clock, 0, 0, 6, 8, 2), (.calendar, 6, 0, 6, 4, 1), (.weather, 6, 4, 6, 4, 3)])),
    ]

    public static var standard: DashboardLayout { presets[0].layout }

    private static func make(_ cells: [(WidgetKind, Int, Int, Int, Int, Int)]) -> DashboardLayout {
        DashboardLayout(items: cells.map { WidgetItem(kind: $0.0, col: $0.1, row: $0.2, cols: $0.3, rows: $0.4, variant: $0.5) })
    }
}
