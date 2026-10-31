import SwiftUI
import BooxSyncCore

/// Where a widget sits on the display. All insets are in "reference pixels" of a 1872 x 1302 display and scale with it.
enum DashboardGeometry {
    static let referenceHeight: CGFloat = 1302

    static func scale(_ size: CGSize) -> CGFloat { max(0.2, size.height / referenceHeight) }

    /// The grid area inside the margins (below the menu bar that macOS draws on top of the display).
    static func gridArea(in size: CGSize, topInset: CGFloat) -> CGRect {
        let s = scale(size)
        let left = 32 * s, top = (topInset + 14) * s, bottom = 32 * s
        return CGRect(x: left, y: top, width: size.width - 2 * left, height: size.height - top - bottom)
    }

    static func cellSize(in size: CGSize, topInset: CGFloat) -> CGSize {
        let area = gridArea(in: size, topInset: topInset)
        return CGSize(width: area.width / CGFloat(DashboardLayout.columns), height: area.height / CGFloat(DashboardLayout.rows))
    }

    static func frame(col: Int, row: Int, cols: Int, rows: Int, in size: CGSize, topInset: CGFloat) -> CGRect {
        let area = gridArea(in: size, topInset: topInset)
        let cell = cellSize(in: size, topInset: topInset)
        let gap = 12 * scale(size)
        return CGRect(x: area.minX + CGFloat(col) * cell.width + gap / 2, y: area.minY + CGFloat(row) * cell.height + gap / 2,
                      width: CGFloat(cols) * cell.width - gap, height: CGFloat(rows) * cell.height - gap)
    }

    static func frame(of item: WidgetItem, in size: CGSize, topInset: CGFloat) -> CGRect {
        frame(col: item.col, row: item.row, cols: item.cols, rows: item.rows, in: size, topInset: topInset)
    }
}

/// Foreground and background of the dashboard. Light is black on white; dark is white on black.
struct DashTheme {
    let fg: Color
    let bg: Color

    static let light = DashTheme(fg: .black, bg: .white)
    static let dark = DashTheme(fg: .white, bg: .black)
}

private struct DashThemeKey: EnvironmentKey {
    static let defaultValue = DashTheme.light
}

extension EnvironmentValues {
    var dashTheme: DashTheme {
        get { self[DashThemeKey.self] }
        set { self[DashThemeKey.self] = newValue }
    }
}

/// Designed for e-ink: black on white, thick outlines, large type, no animation, minute-level updates.
struct DashboardView: View {
    @ObservedObject var model: DashboardModel
    /// Height of the menu bar that macOS draws over the top of the display, in reference pixels.
    var topInset: CGFloat = 37

    var body: some View {
        let theme = model.layout.dark ? DashTheme.dark : DashTheme.light
        return GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                theme.bg
                if model.layout.items.isEmpty {
                    Text("Empty dashboard. Add components in the Dashboard tab.")
                        .font(.system(size: 40 * DashboardGeometry.scale(geo.size), weight: .semibold))
                        .foregroundStyle(theme.fg)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                ForEach(model.layout.items) { item in
                    let rect = DashboardGeometry.frame(of: item, in: geo.size, topInset: topInset)
                    WidgetView(item: item, model: model, outlines: model.layout.outlines, size: rect.size)
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .environment(\.dashTheme, theme)
        .environment(\.colorScheme, model.layout.dark ? .dark : .light)
    }
}
